package com.matrix.matrix_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Testes de JVM do parser de `.wastickers` (o pacote que o WhatsApp
 * compartilha é um ZIP com .webp/.png + contents.json).
 *
 * Sem dependência de Android/emulador: a validação real do fluxo no
 * dispositivo é complementar a estes testes de lógica.
 */
class WastickersParserTest {

    /** PNG mínimo com os magic bytes corretos. */
    private fun pngBytes(): ByteArray = byteArrayOf(
        0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01,
    )

    private fun zipOf(vararg entries: Pair<String, ByteArray>): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            for ((name, bytes) in entries) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(bytes)
                zip.closeEntry()
            }
        }
        return out.toByteArray()
    }

    private fun newDir(): File =
        File.createTempFile("wastickers", "dir").let {
            it.delete()
            it.mkdirs()
            it
        }

    @Test
    fun `extrai figurinhas, capa e metadados de um pacote`() {
        val dir = newDir()
        val zip = zipOf(
            "contents.json" to
                """{"name":"Meu Pack","author":"Autor"}""".toByteArray(),
            "tray.png" to pngBytes(),
            "1.webp" to pngBytes(),
            "2.webp" to pngBytes(),
        )
        val parsed = WastickersParser.parse(ByteArrayInputStream(zip), dir)
        assertTrue(parsed != null)
        assertEquals("Meu Pack", parsed!!.title)
        assertEquals("Autor", parsed.author)
        assertEquals(2, parsed.stickers.size)
        assertTrue(parsed.coverPath!!.endsWith("tray.png"))
        assertEquals("image/webp", parsed.stickers[0].mime)
    }

    @Test
    fun `aceita publisher aninhado em sticker_packs`() {
        val dir = newDir()
        val zip = zipOf(
            "contents.json" to
                """{"sticker_packs":[{"name":"N","publisher":"Pub"}]}""".toByteArray(),
            "s.webp" to pngBytes(),
        )
        val parsed = WastickersParser.parse(ByteArrayInputStream(zip), dir)
        assertEquals("N", parsed!!.title)
        assertEquals("Pub", parsed.author)
    }

    @Test
    fun `rejeita path traversal e nao escreve fora do diretorio`() {
        assertFalse(WastickersParser.isSafeEntryName("../evil.png"))
        assertFalse(WastickersParser.isSafeEntryName("/abs/evil.png"))
        assertFalse(WastickersParser.isSafeEntryName("a\\b.png"))
        assertFalse(WastickersParser.isSafeEntryName("sub/dir.png"))
        assertTrue(WastickersParser.isSafeEntryName("sticker.webp"))

        val dir = newDir()
        val zip = zipOf(
            "../evil.png" to pngBytes(),
            "ok.webp" to pngBytes(),
        )
        val parsed = WastickersParser.parse(ByteArrayInputStream(zip), dir)
        assertEquals(1, parsed!!.stickers.size)
        assertEquals(1, parsed.rejected)
        assertFalse(File(dir.parentFile, "evil.png").exists())
    }

    @Test
    fun `pacote sem imagens retorna null e limpa temporarios`() {
        val dir = newDir()
        val zip = zipOf("readme.txt" to "nada".toByteArray())
        val parsed = WastickersParser.parse(ByteArrayInputStream(zip), dir)
        assertNull(parsed)
        assertFalse(dir.exists())
    }

    @Test
    fun `zip invalido retorna null sem deixar arquivos`() {
        val dir = newDir()
        val parsed = WastickersParser.parse(
            ByteArrayInputStream(byteArrayOf(1, 2, 3, 4, 5)),
            dir,
        )
        assertNull(parsed)
        assertFalse(dir.exists())
    }

    @Test
    fun `limita a quantidade de figurinhas do pacote`() {
        val dir = newDir()
        val entries = ArrayList<Pair<String, ByteArray>>()
        entries.add("contents.json" to """{"name":"Grande"}""".toByteArray())
        for (i in 0 until WastickersParser.MAX_STICKERS + 5) {
            entries.add("$i.webp" to pngBytes())
        }
        val parsed = WastickersParser.parse(
            ByteArrayInputStream(zipOf(*entries.toTypedArray())),
            dir,
        )
        assertEquals(WastickersParser.MAX_STICKERS, parsed!!.stickers.size)
        assertEquals(5, parsed.rejected)
    }

    @Test
    fun `nao aceita imagem acima do limite por arquivo`() {
        val dir = newDir()
        val big = ByteArray((WastickersParser.MAX_FILE_BYTES + 1024).toInt())
        val zip = zipOf("huge.webp" to big)
        val parsed = WastickersParser.parse(ByteArrayInputStream(zip), dir)
        assertNull(parsed)
        assertFalse(dir.exists())
    }

    @Test
    fun `title_txt define o nome e os metadados nao bloqueiam`() {
        val dir = newDir()
        val zip = zipOf(
            "author.txt" to "Fulano".toByteArray(),
            "s.png" to pngBytes(),
        )
        val parsed = WastickersParser.parse(ByteArrayInputStream(zip), dir)
        assertEquals("Fulano", parsed!!.author)
        assertEquals("", parsed.title) // a tela usa um default nesse caso
    }
}
