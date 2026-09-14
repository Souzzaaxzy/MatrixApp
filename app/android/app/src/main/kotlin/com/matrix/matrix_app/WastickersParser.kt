package com.matrix.matrix_app

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.util.zip.ZipInputStream

/** Uma figurinha extraída de um pacote. */
data class PackedSticker(
    val path: String,
    val name: String,
    val mime: String,
    val size: Long,
)

/** Resultado de abrir um `.wastickers`. */
data class ParsedPack(
    val title: String,
    val author: String,
    val coverPath: String?,
    val stickers: List<PackedSticker>,
    val rejected: Int,
)

/**
 * Abre um pacote `.wastickers` — que é, na prática, um ZIP com os `.webp`/
 * `.png` das figurinhas, um ícone de bandeja e um `contents.json` com
 * título/autor.
 *
 * É lógica PURA de JVM (sem APIs do Android) para poder ser testada
 * unitariamente: nada do conteúdo é executado, apenas lido como dados, com
 * limites de tamanho/quantidade e proteção contra path traversal.
 */
object WastickersParser {
    const val MAX_STICKERS = 60
    const val MAX_FILE_BYTES = 5L * 1024 * 1024
    const val MAX_TOTAL_BYTES = 30L * 1024 * 1024
    const val MAX_METADATA_BYTES = 64 * 1024

    /**
     * Extrai [input] para [destDir]. Retorna `null` quando o ZIP é inválido,
     * passou dos limites ou não contém nenhuma imagem compatível (nesses
     * casos [destDir] é removido — nenhum temporário sobra).
     */
    fun parse(input: InputStream, destDir: File): ParsedPack? {
        if (!destDir.mkdirs() && !destDir.isDirectory) return null
        var total = 0L
        var rejected = 0
        val stickers = ArrayList<PackedSticker>()
        var coverPath: String? = null
        var title = ""
        var author = ""

        try {
            ZipInputStream(input.buffered()).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    if (entry.isDirectory) {
                        zip.closeEntry()
                        continue
                    }
                    val name = entry.name ?: ""
                    if (!isSafeEntryName(name)) {
                        rejected++
                        zip.closeEntry()
                        continue
                    }
                    val lower = name.lowercase()
                    when {
                        lower.endsWith("contents.json") -> {
                            val meta = parseMetadata(readTextCapped(zip))
                            if (title.isEmpty()) title = meta.first
                            if (author.isEmpty()) author = meta.second
                        }
                        lower.endsWith("title.txt") || lower.endsWith("name.txt") -> {
                            val text = readTextCapped(zip).trim()
                            if (title.isEmpty() && text.isNotEmpty()) title = text
                        }
                        lower.endsWith("author.txt") || lower.endsWith("publisher.txt") -> {
                            val text = readTextCapped(zip).trim()
                            if (author.isEmpty() && text.isNotEmpty()) author = text
                        }
                        isImageEntry(lower) -> {
                            val isCover = coverPath == null &&
                                (lower.contains("tray") || lower.contains("icon") ||
                                    lower.contains("cover"))
                            if (!isCover && stickers.size >= MAX_STICKERS) {
                                rejected++
                                zip.closeEntry()
                                continue
                            }
                            val dest = File(destDir, sanitize(File(name).name))
                            total = writeCapped(zip, dest, total)
                            if (total < 0) {
                                destDir.deleteRecursively()
                                return null
                            }
                            val sticker = PackedSticker(
                                path = dest.absolutePath,
                                name = File(name).name,
                                mime = mimeForName(lower) ?: "image/webp",
                                size = dest.length(),
                            )
                            if (isCover) coverPath = sticker.path else stickers.add(sticker)
                        }
                    }
                    zip.closeEntry()
                }
            }
        } catch (_: Exception) {
            destDir.deleteRecursively()
            return null
        }

        if (stickers.isEmpty()) {
            destDir.deleteRecursively()
            return null
        }
        return ParsedPack(
            title = title.take(40),
            author = author.take(60),
            coverPath = coverPath,
            stickers = stickers,
            rejected = rejected,
        )
    }

    /** Impede path traversal/entradas absolutas ou com separadores. */
    fun isSafeEntryName(name: String): Boolean {
        if (name.startsWith("/") || name.contains("..") || name.contains('\\')) {
            return false
        }
        if (name.contains(":") || name.startsWith(".")) return false
        // O .wastickers usa nomes planos; subpastas são descartadas.
        return File(name).name == name
    }

    fun isImageEntry(lower: String): Boolean =
        lower.endsWith(".webp") || lower.endsWith(".png") ||
            lower.endsWith(".jpg") || lower.endsWith(".jpeg")

    fun mimeForName(lower: String): String? = when {
        lower.endsWith(".webp") -> "image/webp"
        lower.endsWith(".png") -> "image/png"
        lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
        else -> null
    }

    /** Extrai (título, autor) de `contents.json` — tolerante a formatos.
     *
     * O arquivo pode trazer `{"name":..., "author":...}` no topo ou dentro de
     * `sticker_packs[0]` (`{"name":..., "publisher":...}`). Um scanner simples
     * evita dependência de JSON e aceita variações.
     */
    fun parseMetadata(text: String): Pair<String, String> {
        val title = firstString(text, "name").orEmpty()
        val author = firstString(text, "author")
            ?: firstString(text, "publisher")
            ?: ""
        return title to author
    }

    /** Primeiro valor string de [key] no texto (scanner tolerante). */
    private fun firstString(text: String, key: String): String? {
        val marker = "\"$key\""
        var index = text.indexOf(marker)
        while (index >= 0) {
            var i = index + marker.length
            while (i < text.length && text[i].isWhitespace()) i++
            if (i < text.length && text[i] == ':') {
                i++
                while (i < text.length && text[i].isWhitespace()) i++
                if (i < text.length && text[i] == '"') {
                    val sb = StringBuilder()
                    i++
                    while (i < text.length && text[i] != '"') {
                        if (text[i] == '\\' && i + 1 < text.length) i++
                        sb.append(text[i])
                        i++
                    }
                    return sb.toString()
                }
            }
            index = text.indexOf(marker, index + marker.length)
        }
        return null
    }

    /** Copia no máximo [MAX_FILE_BYTES] respeitando [alreadyWritten]. */
    fun writeCapped(input: InputStream, dest: File, alreadyWritten: Long): Long {
        var written = alreadyWritten
        dest.outputStream().use { output ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                written += read
                if (written > MAX_TOTAL_BYTES) return -1L
                output.write(buffer, 0, read)
            }
        }
        if (dest.length() > MAX_FILE_BYTES) return -1L
        return written
    }

    /** Lê um texto pequeno do zip com cap (metadados). */
    fun readTextCapped(input: InputStream): String {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(4096)
        var total = 0
        while (true) {
            val read = input.read(buffer)
            if (read <= 0) break
            total += read
            if (total > MAX_METADATA_BYTES) break
            out.write(buffer, 0, read)
        }
        return String(out.toByteArray(), Charsets.UTF_8)
    }

    fun sanitize(name: String): String {
        val base = File(name).name
        return base.replace(Regex("[^A-Za-z0-9._-]"), "_").ifEmpty { "sticker" }
    }
}
