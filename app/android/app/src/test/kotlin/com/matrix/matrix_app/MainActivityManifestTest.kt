package com.matrix.matrix_app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Guarda de regressão do compartilhamento com UMA única instância.
 *
 * O bug relatado ("cada share abre um MATRIX novo") vinha da configuração da
 * Activity no manifesto. Este teste lê o `AndroidManifest.xml` real e falha
 * se alguém reintroduzir a configuração quebrada — sem precisar de emulador.
 *
 * (O diretório de trabalho dos testes unitários Android é `android/app`,
 * então o caminho é relativo ao módulo.)
 */
class MainActivityManifestTest {

    private fun manifest(): String {
        val candidates = listOf(
            File("src/main/AndroidManifest.xml"),
            File("app/src/main/AndroidManifest.xml"),
        )
        val file = candidates.firstOrNull { it.exists() }
        requireNotNull(file) {
            "AndroidManifest.xml não encontrado (cwd=${File(".").absolutePath})"
        }
        return file.readText()
    }

    private fun activityBlock(xml: String): String {
        val start = xml.indexOf(".MainActivity")
        require(start >= 0) { "MainActivity não declarada no manifesto" }
        // Recorta a tag <activity ...> que contém MainActivity.
        val tagStart = xml.lastIndexOf("<activity", start)
        val tagEnd = xml.indexOf('>', start)
        return xml.substring(tagStart, tagEnd + 1)
    }

    @Test
    fun `usa launchMode singleTask para ter uma unica instancia`() {
        val block = activityBlock(manifest())
        assertTrue(
            "MainActivity precisa de launchMode=singleTask (uma instância por sistema; " +
                "novos shares chegam por onNewIntent). Bloco: $block",
            block.contains("android:launchMode=\"singleTask\""),
        )
        // singleTop NÃO é suficiente: só reaproveita se a Activity estiver no
        // topo da própria task — em segundo plano gerava novas instâncias.
        assertFalse(
            "singleTop não garante instância única no fluxo de compartilhamento.",
            block.contains("android:launchMode=\"singleTop\""),
        )
    }

    @Test
    fun `nao define taskAffinity vazio`() {
        val block = activityBlock(manifest())
        assertFalse(
            "taskAffinity=\"\" dá à Activity nenhuma afinidade e faz cada launch " +
                "criar uma task nova (causa do bug de múltiplas janelas).",
            block.contains("android:taskAffinity=\"\""),
        )
    }

    @Test
    fun `declara os filtros de compartilhamento esperados`() {
        val xml = manifest()
        assertTrue(xml.contains("android.intent.action.SEND\""))
        assertTrue(xml.contains("android.intent.action.SEND_MULTIPLE\""))
        assertTrue(xml.contains("android.intent.category.LAUNCHER"))
    }
}
