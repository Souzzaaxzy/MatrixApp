package com.matrix.matrix_app

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.util.concurrent.Executors

/**
 * MATRIX main activity.
 *
 * Além do launcher padrão, a activity recebe figuritas pelo compartilhamento
 * nativo do Android. O WhatsApp NÃO envia um pacote de figurinhas como várias
 * imagens: ele manda UM arquivo `.wastickers` (um ZIP com os .webp/.png e o
 * título/autor) — por isso o filtro do manifesto cobre `image`, `application`
 * e curinga de MIME.
 *
 * O que acontece aqui:
 *  * `onCreate` trata o share que ABRIU o app (processo frio).
 *  * `onNewIntent` trata um share recebido com o app JÁ aberto — reutilizando
 *    a instância (launchMode="singleTop"), sem criar outra janela/task.
 *  * Cada intent é processado UMA única vez (assinatura + "consumo" do
 *    intent), o que evita loops/importações duplicadas em recriações.
 *  * `EXTRA_STREAM` e `ClipData` são verificados (alguns apps só usam o
 *    segundo).
 *  * Os `content://` são lidos na hora (permissão temporária
 *    FLAG_GRANT_READ_URI_PERMISSION) e copiados para o cache privado do app.
 *  * Um pacote `.wastickers`/ZIP é aberto com proteção contra path traversal,
 *    limites de quantidade/tamanho e limpeza em caso de erro.
 *  * O resultado (imagens soltas OU pacote) vai para o Flutter pelo canal
 *    `matrix.share/stickers`; o Flutter valida os bytes e abre a tela de
 *    importação.
 *
 * Nada é executado do conteúdo recebido — arquivos externos são somente dados.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "matrix.share/stickers"
        private const val TAG = "MatrixShare"

        // Limites de segurança (espelham/antecedem o servidor).
        private const val MAX_STICKERS = 60
        private const val MAX_FILE_BYTES = 5 * 1024 * 1024L
        private const val MAX_TOTAL_BYTES = 30 * 1024 * 1024L

        private const val KIND_IMAGES = "images"
        private const val KIND_PACK = "pack"
        private const val KIND_ERROR = "error"

        /**
         * Contador de instâncias de MainActivity criadas neste processo —
         * apenas para diagnóstico (o fluxo corrigido mantém 1).
         */
        private val instanceCounter = java.util.concurrent.atomic.AtomicInteger(0)

        private fun nextInstanceSeq(): Int = instanceCounter.incrementAndGet()
    }

    private var channel: MethodChannel? = null

    /** Lote pronto aguardando o Flutter (processo frio) ou o push. */
    private var pendingBatch: Map<String, Any?>? = null

    /** Há um lote sendo montado na worker thread (processo frio). */
    private var processing = false

    /** Consulta de "initialSharedBatch" à espera do lote em andamento. */
    private var deferredInitialResult: MethodChannel.Result? = null

    /** Assinatura do último intent processado — evita reprocessar o mesmo. */
    private var lastProcessedSignature: String? = null

    /**
     * Contador de instâncias desta Activity no processo. Só para diagnóstico:
     * com o fluxo corrigido (launchMode singleTask) ele permanece em 1 —
     * é o que confirma nos logs que compartilhamentos repetidos chegam à
     * MESMA instância. (Não é usado para nenhuma lógica de negócio.)
     */
    private val instanceSeq = nextInstanceSeq()

    /** Contador monotônico para os `batchId` (nunca colide). */
    private var batchSeq = 0L

    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(
            TAG,
            "onCreate instance=$instanceSeq taskId=${taskId} " +
                "action=${intent?.action}",
        )
        // Processo novo: limpa temporários de shares anteriores (o Flutter
        // ainda não tem nada pendente, então não há risco de apagar um lote
        // que ainda será importado).
        purgeSharedCache()
        // Share que abriu o app (processo frio). A entrega ao Flutter
        // acontece no configureFlutterEngine (o canal ainda não existe aqui).
        handleShareIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            if (call.method == "initialSharedBatch") {
                val batch = pendingBatch
                if (batch != null) {
                    pendingBatch = null
                    result.success(batch)
                } else if (processing) {
                    // A worker ainda está montando o lote (processo frio):
                    // responde quando ele terminar — o share não se perde.
                    deferredInitialResult = result
                } else {
                    result.success(null)
                }
            }
        }
        // Se um share já foi processado antes do canal existir (processo
        // frio), a consulta "initialSharedBatch" o buscará. Nada a fazer.
    }

    override fun onNewIntent(intent: Intent) {
        // super primeiro: mantém o comportamento do embedding Flutter e dos
        // plugins (ex.: flutter_local_notifications lê o intent aqui).
        super.onNewIntent(intent)
        Log.d(
            TAG,
            "onNewIntent instance=$instanceSeq taskId=${taskId} " +
                "action=${intent.action}",
        )
        setIntent(intent)
        // App JÁ aberto (ou trazido do segundo plano) recebeu um novo share —
        // entrega na MESMA instância e limpa o intent para não reprocessar.
        handleShareIntent(intent)
    }

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }

    // ── Captura do conteúdo compartilhado ────────────────────

    private fun handleShareIntent(intent: Intent?) {
        intent ?: return
        val action = intent.action ?: return
        val isShare = action == Intent.ACTION_SEND ||
            action == Intent.ACTION_SEND_MULTIPLE ||
            action == Intent.ACTION_VIEW
        if (!isShare) return

        val uris = extractUris(intent)
        val mime = intent.type?.lowercase() ?: ""

        val signature = action + "|" + mime + "|" +
            uris.joinToString(",") { it.toString() }
        if (signature == lastProcessedSignature) {
            Log.d(TAG, "Intent repetido ignorado: $signature")
            consumeIntent(intent)
            return
        }
        lastProcessedSignature = signature
        Log.d(
            TAG,
            "Share recebido: action=$action mime=$mime uris=${uris.size} " +
                "hasStream=${intent.hasExtra(Intent.EXTRA_STREAM)} " +
                "hasClipData=${intent.clipData != null}",
        )

        // Consome o intent imediatamente: mesmo que a Activity seja
        // recriada, o mesmo conteúdo não dispara outra importação.
        consumeIntent(intent)

        if (uris.isEmpty()) {
            deliverBatch(
                error("O conteúdo compartilhado não é compatível com o MATRIX."),
            )
            return
        }

        processing = true
        worker.execute {
            val batch = try {
                buildBatch(intent, uris, mime)
            } catch (e: Exception) {
                Log.e(TAG, "Falha ao processar share", e)
                error("Não foi possível acessar os arquivos compartilhados.")
            }
            mainHandler.post {
                processing = false
                deliverBatch(batch)
            }
        }
    }

    /**
     * Coleta os `content://`/`file://` do intent. Verifica `EXTRA_STREAM`
     * (Uri único ou lista) E `ClipData` — alguns remetentes usam só um deles.
     */
    @Suppress("DEPRECATION")
    private fun extractUris(intent: Intent): List<Uri> {
        val out = LinkedHashSet<Uri>()

        when (intent.action) {
            Intent.ACTION_SEND -> {
                val single = if (android.os.Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
                if (single != null) out.add(single)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val many = if (android.os.Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                many?.forEach { if (it != null) out.add(it) }
            }
            Intent.ACTION_VIEW -> intent.data?.let { out.add(it) }
        }

        // ClipData (aparece quando o remetente monta o share por clip).
        val clip: ClipData? = intent.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) {
                clip.getItemAt(i).uri?.let { out.add(it) }
            }
        }

        // Nunca confiar em conteúdo sem esquema suportado.
        return out.filter { it.scheme == "content" || it.scheme == "file" }
    }

    private fun consumeIntent(intent: Intent) {
        intent.removeExtra(Intent.EXTRA_STREAM)
        intent.clipData = null
    }

    // ── Montagem do lote (roda fora da thread principal) ─────

    private fun buildBatch(
        intent: Intent,
        uris: List<Uri>,
        declaredMime: String,
    ): Map<String, Any?> {
        val origin = intent.`package` ?: ""

        // 1) Pacote .wastickers/ZIP (1 arquivo) → abrir como pacote.
        if (uris.size == 1 && isZipShare(uris[0], declaredMime)) {
            val packed = tryOpenPack(uris[0], origin)
            if (packed != null) return packed
            // Não era um ZIP válido → segue para o caminho de imagens.
        }

        // 2) Imagens soltas (ACTION_SEND / ACTION_SEND_MULTIPLE).
        val stickers = ArrayList<Map<String, Any?>>()
        var rejected = 0
        for (uri in uris) {
            if (stickers.size >= MAX_STICKERS) {
                rejected++
                continue
            }
            val copied = copyUri(uri, "shared_stickers", origin)
            if (copied != null) stickers.add(copied) else rejected++
        }

        if (stickers.isEmpty()) {
            return error("Não foi possível acessar os arquivos compartilhados.")
        }
        return batch(
            kind = KIND_IMAGES,
            stickers = stickers,
            origin = origin,
            rejected = rejected,
        )
    }

    /** Um share é tratado como pacote quando é ZIP pelos bytes/MIME/extensão. */
    private fun isZipShare(uri: Uri, declaredMime: String): Boolean {
        if (declaredMime.contains("wastickers") || declaredMime.contains("zip")) {
            return true
        }
        val name = queryDisplayName(uri)?.lowercase() ?: ""
        if (name.endsWith(".wastickers") || name.endsWith(".zip")) return true
        return hasZipMagic(uri)
    }

    private fun hasZipMagic(uri: Uri): Boolean {
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                val head = ByteArray(4)
                val read = input.read(head)
                read >= 4 &&
                    head[0] == 0x50.toByte() && head[1] == 0x4B.toByte() &&
                    (head[2] == 0x03.toByte() || head[2] == 0x05.toByte() ||
                        head[2] == 0x07.toByte())
            } ?: false
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Extrai um `.wastickers` (ZIP) para o cache privado e devolve um lote
     * `pack` com capa/título/autor + figurinhas. Retorna null quando o ZIP
     * é inválido ou não contém nenhuma imagem compatível.
     */
    private fun tryOpenPack(uri: Uri, origin: String): Map<String, Any?>? {
        val dir = File(cacheDir, "shared_stickers/pack-${System.currentTimeMillis()}")
        val parsed = try {
            contentResolver.openInputStream(uri)?.use { raw ->
                WastickersParser.parse(raw, dir)
            } ?: return null
        } catch (e: Exception) {
            Log.e(TAG, "Falha ao abrir pacote .wastickers", e)
            dir.deleteRecursively()
            return null
        } ?: return null

        var title = parsed.title
        if (title.isBlank()) {
            title = queryDisplayName(uri)
                ?.substringBeforeLast('.')
                ?.take(40)
                ?.ifBlank { null }
                ?: "Pacote compartilhado"
        }
        val stickers = parsed.stickers.map { s ->
            mapOf(
                "path" to s.path,
                "name" to s.name,
                "mime" to s.mime,
                "size" to s.size,
            )
        }
        return batch(
            kind = KIND_PACK,
            stickers = stickers,
            origin = origin,
            title = title.take(40),
            author = parsed.author.take(60),
            coverPath = parsed.coverPath,
            rejected = parsed.rejected,
        )
    }

    // ── Cópia segura de um URI avulso ────────────────────────

    private fun copyUri(uri: Uri, subdir: String, origin: String): Map<String, Any?>? {
        return try {
            val mime = contentResolver.getType(uri)?.lowercase() ?: ""
            val display = queryDisplayName(uri)
                ?: "stickers-${System.currentTimeMillis()}.img"
            // Aceita só o que pode ser figurinha: imagens declaradas, ou
            // arquivos sem MIME confiável (o Flutter valida os magic bytes).
            val lookOk = mime.isEmpty() || mime.startsWith("image/") ||
                mime == "application/octet-stream" ||
                mime.contains("wastickers") || mime.contains("zip")
            if (!lookOk) return null

            val dir = File(cacheDir, subdir).apply { mkdirs() }
            val dest = File(dir, sanitize(display))
            contentResolver.openInputStream(uri)?.use { input ->
                if (writeCapped(input, dest, 0L) < 0L) {
                    dest.delete()
                    return null
                }
            } ?: return null
            if (!dest.exists() || dest.length() == 0L) {
                dest.delete()
                return null
            }
            mapOf(
                "path" to dest.absolutePath,
                "name" to display,
                "mime" to mime,
                "size" to dest.length(),
            )
        } catch (e: Exception) {
            Log.e(TAG, "Falha ao copiar uri compartilhado", e)
            null
        }
    }

    // ── Utilidades ───────────────────────────────────────────

    /** Remove temporários do compartir anterior (nunca a coleção do usuário). */
    private fun purgeSharedCache() {
        try {
            File(cacheDir, "shared_stickers").deleteRecursively()
        } catch (e: Exception) {
            Log.w(TAG, "Não foi possível limpar o cache de compartilhamento", e)
        }
    }

    /** Copia no máximo MAX_FILE_BYTES respeitando [alreadyWritten]. */
    private fun writeCapped(input: InputStream, dest: File, alreadyWritten: Long): Long =
        WastickersParser.writeCapped(input, dest, alreadyWritten)

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) cursor.getString(idx) else null
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun sanitize(name: String): String {
        val base = File(name).name
        return base.replace(Regex("[^A-Za-z0-9._-]"), "_").ifEmpty { "sticker" }
    }

    // ── Montagem/entrega do lote ─────────────────────────────

    private fun batch(
        kind: String,
        stickers: List<Map<String, Any?>>,
        origin: String = "",
        title: String = "",
        author: String = "",
        coverPath: String? = null,
        rejected: Int = 0,
    ): Map<String, Any?> = mapOf(
        "kind" to kind,
        "title" to title,
        "author" to author,
        "coverPath" to coverPath,
        "origin" to origin,
        "rejected" to rejected,
        "batchId" to "${System.currentTimeMillis()}-${batchSeq++}-$instanceSeq",
        "stickers" to stickers,
    )

    private fun error(message: String): Map<String, Any?> = mapOf(
        "kind" to KIND_ERROR,
        "error" to message,
        "stickers" to emptyList<Map<String, Any?>>(),
        "batchId" to "err-${System.currentTimeMillis()}-${batchSeq++}",
    )

    private fun deliverBatch(batch: Map<String, Any?>) {
        pendingBatch = batch
        val ch = channel
        if (ch != null) {
            // App já em execução: empurra o novo lote (o Flutter deduplica).
            ch.invokeMethod("onSharedBatch", batch)
        }
        // Processo frio: o Flutter pode ter consultado antes do lote ficar
        // pronto — responde agora.
        val deferred = deferredInitialResult
        if (deferred != null) {
            deferredInitialResult = null
            pendingBatch = null
            deferred.success(batch)
        }
    }
}
