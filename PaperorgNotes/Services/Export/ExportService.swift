import Foundation
import PDFKit
import UIKit

@MainActor
final class ExportService {
    let storage: StorageService
    
    init(storage: StorageService) {
        self.storage = storage
    }
    
    func exportPlainText(note: Note) throws -> URL {
        let content = buildTextContent(note: note)
        return try writeExport(content: content, noteId: note.id, extension: "txt")
    }
    
    func exportMarkdown(note: Note) throws -> URL {
        let md = buildMarkdown(note: note)
        return try writeExport(content: md, noteId: note.id, extension: "md")
    }
    
    func exportPDF(note: Note) throws -> URL {
        let content = buildTextContent(note: note)
        let pdfData = renderPDF(title: note.title, body: content)
        let url = storage.exportsDirectory.appendingPathComponent("\(note.id.uuidString)-\(timestamp()).pdf")
        try pdfData.write(to: url)
        return url
    }
    
    func exportRTF(note: Note) throws -> URL {
        let content = buildTextContent(note: note)
        let attributed = NSAttributedString(string: content, attributes: [
            .font: UIFont.systemFont(ofSize: 12)
        ])
        let range = NSRange(location: 0, length: attributed.length)
        let data = try attributed.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let url = storage.exportsDirectory.appendingPathComponent("\(note.id.uuidString)-\(timestamp()).rtf")
        try data.write(to: url)
        return url
    }
    
    func audioURL(for note: Note) -> URL? {
        let url = storage.audioURL(for: note.id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    
    private func buildTextContent(note: Note) -> String {
        var parts: [String] = []
        parts.append(note.title)
        parts.append("Date: \(formattedDate(note.createdAt))")
        parts.append("Language: \(note.appLanguage.displayName)")
        parts.append("")
        
        if let summary = note.summaryShort, !summary.isEmpty {
            parts.append("SUMMARY")
            parts.append(summary)
            parts.append("")
        }
        
        if let structured = note.structuredOutput {
            if !structured.actionItems.isEmpty {
                parts.append("ACTION ITEMS")
                for item in structured.actionItems {
                    parts.append("- \(item.text)")
                }
                parts.append("")
            }
            if !structured.decisions.isEmpty {
                parts.append("DECISIONS")
                for d in structured.decisions { parts.append("- \(d)") }
                parts.append("")
            }
        }
        
        parts.append("TRANSCRIPT")
        parts.append(note.displayTranscript)
        
        return parts.joined(separator: "\n")
    }
    
    private func buildMarkdown(note: Note) -> String {
        var md = "# \(note.title)\n\n"
        md += "**Date:** \(formattedDate(note.createdAt))  \n"
        md += "**Language:** \(note.appLanguage.displayName)  \n\n"
        
        if let summary = note.summaryShort, !summary.isEmpty {
            md += "## Summary\n\n\(summary)\n\n"
        }
        
        if let structured = note.structuredOutput {
            if !structured.actionItems.isEmpty {
                md += "## Action Items\n\n"
                for item in structured.actionItems {
                    md += "- [ ] \(item.text)\n"
                }
                md += "\n"
            }
            if !structured.decisions.isEmpty {
                md += "## Decisions\n\n"
                for d in structured.decisions { md += "- \(d)\n" }
                md += "\n"
            }
        }
        
        md += "## Transcript\n\n\(note.displayTranscript)\n"
        return md
    }
    
    private func renderPDF(title: String, body: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        return renderer.pdfData { context in
            context.beginPage()
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18)
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11)
            ]
            
            title.draw(at: CGPoint(x: 40, y: 40), withAttributes: titleAttrs)
            body.draw(in: CGRect(x: 40, y: 80, width: 532, height: 692), withAttributes: bodyAttrs)
        }
    }
    
    private func writeExport(content: String, noteId: UUID, extension ext: String) throws -> URL {
        let url = storage.exportsDirectory.appendingPathComponent("\(noteId.uuidString)-\(timestamp()).\(ext)")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    private func timestamp() -> Int {
        Int(Date.now.timeIntervalSince1970)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
