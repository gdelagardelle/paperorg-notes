package com.paperorg.notes.data

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import com.paperorg.notes.domain.Note
import com.paperorg.notes.domain.NoteDocument
import com.paperorg.notes.domain.NoteExport
import java.io.File

object PdfNoteWriter {
    private const val PAGE_WIDTH = 612
    private const val PAGE_HEIGHT = 792
    private const val MARGIN = 40f
    private const val NAVY = 0xFF142337.toInt()
    private const val ORANGE = 0xFFF56A0A.toInt()
    private const val SECONDARY = 0xFF4D607B.toInt()
    private const val WHITE = 0xFFFFFFFF.toInt()

    fun write(note: Note, destDir: File): File {
        destDir.mkdirs()
        val document = NoteExport.document(note)
        val file = File(destDir, "${note.id}.pdf")
        val pdf = PdfDocument()
        try {
            var remaining = document.body
            var pageIndex = 0
            do {
                val info = PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageIndex + 1).create()
                val page = pdf.startPage(info)
                val top = drawChrome(page.canvas, document, pageIndex)
                remaining = drawBody(page.canvas, remaining, top)
                pdf.finishPage(page)
                pageIndex += 1
            } while (remaining.isNotEmpty() && pageIndex <= 200)
            file.outputStream().use { pdf.writeTo(it) }
        } finally {
            pdf.close()
        }
        return file
    }

    private fun drawChrome(canvas: Canvas, document: NoteDocument, pageIndex: Int): Float {
        canvas.drawRect(0f, 0f, PAGE_WIDTH.toFloat(), 64f, paint(NAVY))
        canvas.drawRect(0f, 64f, PAGE_WIDTH.toFloat(), 67f, paint(ORANGE))
        canvas.drawText("Paperorg Notes", MARGIN, 40f, paint(WHITE, 14f, bold = true))
        if (pageIndex > 0) return MARGIN + 8f
        var y = 67f + MARGIN
        canvas.drawText(document.title, MARGIN, y + 18f, paint(NAVY, 18f, bold = true))
        y += 36f
        canvas.drawText(document.meta, MARGIN, y, paint(SECONDARY, 10f))
        return y + 24f
    }

    private fun drawBody(canvas: Canvas, text: String, top: Float): String {
        if (text.isEmpty()) return ""
        val width = (PAGE_WIDTH - 2 * MARGIN).toInt()
        val available = PAGE_HEIGHT - MARGIN - top
        if (available < 16f) return text
        val bodyPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = NAVY
            textSize = 11f
        }
        val layout = StaticLayout.Builder
            .obtain(text, 0, text.length, bodyPaint, width)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setIncludePad(false)
            .build()
        var end = text.length
        for (index in 0 until layout.lineCount) {
            if (layout.getLineBottom(index) > available) {
                end = layout.getLineStart(index)
                break
            }
        }
        if (end <= 0) {
            end = layout.getLineEnd(0).coerceAtMost(text.length)
        }
        val pageText = text.substring(0, end)
        val pageLayout = StaticLayout.Builder
            .obtain(pageText, 0, pageText.length, bodyPaint, width)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setIncludePad(false)
            .build()
        canvas.save()
        canvas.translate(MARGIN, top)
        pageLayout.draw(canvas)
        canvas.restore()
        return text.substring(end).trimStart()
    }

    private fun paint(color: Int, size: Float = 12f, bold: Boolean = false): Paint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            textSize = size
            isFakeBoldText = bold
        }
}
