package com.matrix.matrix_app

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * MATRIX main activity.
 *
 * Além do launcher padrão, a activity também recebe figurinhas via o menu
 * nativo de compartilhamento do Android (ACTION_SEND / ACTION_SEND_MULTIPLE
 * de imagens PNG/WebP/JPEG). Os URIs recebidos são copiados para o cache do
 * app (read-only content:// da origem) e entregues ao Flutter pelo método
 * "onSharedStickers". O Flutter valida MIME/bytes e abre a tela de
 * importação — nada é adicionado à coleção sem confirmação do usuário.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "matrix.share/stickers"
    }

    private var channel: MethodChannel? = null
    private var pendingSharedFiles: List<Map<String, Any>>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        // O Flutter consulta o estado inicial (app aberto pelo share com o
        // processo frio) e também recebe pushes quando já está em execução.
        ch.setMethodCallHandler { call, result ->
            if (call.method == "initialSharedFiles") {
                val files = pendingSharedFiles
                pendingSharedFiles = null
                result.success(files)
            }
        }
        // A intent que abriu o app (share) é processada aqui, antes do
        // Flutter estar pronto — o resultado fica em pendingSharedFiles para
        // o handler "initialSharedFiles" buscar, e também é empurrado.
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // App JA aberto em segundo plano recebeu um novo share.
        handleShareIntent(intent)
    }

    @Suppress("DEPRECATION")
    private fun handleShareIntent(intent: Intent?) {
        intent ?: return
        val action = intent.action ?: return
        val files = mutableListOf<Map<String, Any>>()

        when (action) {
            Intent.ACTION_SEND -> {
                val uri = if (android.os.Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("UNCHECKED_CAST")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
                if (uri != null) {
                    copyUri(uri)?.let { files.add(it) }
                }
            }

            Intent.ACTION_SEND_MULTIPLE -> {
                val streams = if (android.os.Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("UNCHECKED_CAST")
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                streams?.forEach { uri ->
                    copyUri(uri)?.let { files.add(it) }
                }
            }
        }

        if (files.isNotEmpty()) {
            pendingSharedFiles = files
            channel?.invokeMethod("onSharedStickers", files)
        } else {
            // Nada copiável (ex.: mime inválido) — não deixa re-trigger.
            pendingSharedFiles = null
        }
    }

    /**
     * Copia o conteúdo referenciado por [uri] para o cache do app (diretório
     * privado) e devolve um mapa com path/nome/mimetype/tamanho. Retorna null
     * quando o arquivo não pôde ser lido ou o mimetype não é compatível.
     */
    private fun copyUri(uri: Uri): Map<String, Any>? {
        return try {
            val resolver = contentResolver
            val mime = resolver.getType(uri) ?: return null
            if (!mime.startsWith("image/")) return null

            val name = queryDisplayName(uri)
                ?: "stickers-${System.currentTimeMillis()}.img"
            val dir = File(cacheDir, "shared_stickers").apply { mkdirs() }
            val dest = File(dir, sanitize(name))
            resolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            if (!dest.exists() || dest.length() == 0L) {
                dest.delete()
                return null
            }
            mapOf(
                "path" to dest.absolutePath,
                "name" to name,
                "mime" to mime,
                "size" to dest.length(),
            )
        } catch (_: Exception) {
            null
        }
    }

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
}
