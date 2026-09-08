package com.paperorg.notes

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

class I18nTest {
    @Test
    fun frenchAndGermanCoverEveryDefaultString() {
        val en = names("src/main/res/values/strings.xml")
        val fr = names("src/main/res/values-fr/strings.xml")
        val de = names("src/main/res/values-de/strings.xml")
        assertTrue("default catalog is empty", en.isNotEmpty())
        assertEquals(en, fr)
        assertEquals(en, de)
    }

    @Test
    fun localeFilesAreNotBlank() {
        for (path in listOf(
            "src/main/res/values/strings.xml",
            "src/main/res/values-fr/strings.xml",
            "src/main/res/values-de/strings.xml",
        )) {
            val values = texts(path)
            assertTrue(path, values.isNotEmpty())
            assertTrue(path, values.none { it.isBlank() })
        }
    }

    @Test
    fun luxAsrIsWrittenAsOneWord() {
        val forbidden = listOf("Lux ASR", "Lux asr", "lux asr", "LUX ASR", "Lux Asr")
        for (path in listOf(
            "src/main/res/values/strings.xml",
            "src/main/res/values-fr/strings.xml",
            "src/main/res/values-de/strings.xml",
        )) {
            val xml = File(path).readText()
            forbidden.forEach { variant ->
                assertTrue("$path must not contain '$variant'", !xml.contains(variant))
            }
            assertTrue("$path must name LuxASR", xml.contains("LuxASR"))
        }
    }

    private fun names(path: String): Set<String> {
        val file = File(path)
        assertTrue(file.path, file.isFile)
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val nodes = doc.getElementsByTagName("string")
        return (0 until nodes.length).map { nodes.item(it).attributes.getNamedItem("name").nodeValue }.toSet()
    }

    private fun texts(path: String): List<String> {
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(File(path))
        val nodes = doc.getElementsByTagName("string")
        return (0 until nodes.length).map { nodes.item(it).textContent }
    }
}
