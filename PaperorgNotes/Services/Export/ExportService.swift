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
    
    func exportPDF(note: Note, branded: Bool = false) throws -> URL {
        let content = buildTextContent(note: note)
        let pdfData = renderPDF(title: note.title, body: content, note: note, branded: branded)
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

    func deleteArtifact(at url: URL) throws {
        try storage.deleteExportArtifact(at: url)
    }

    @discardableResult
    func purgeArtifacts(olderThan cutoff: Date) -> [URL] {
        storage.purgeExportArtifacts(olderThan: cutoff)
    }
    
    private func buildTextContent(note: Note) -> String {
        var parts: [String] = []
        parts.append(note.title)
        parts.append("Date: \(formattedDate(note.createdAt))")
        parts.append("Language: \(note.appLanguage.displayName)")
        parts.append("")
        
        if !note.displaySummaryShort.isEmpty {
            parts.append("SUMMARY")
            parts.append(note.displaySummaryShort)
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
        
        if !note.displaySummaryShort.isEmpty {
            md += "## Summary\n\n\(note.displaySummaryShort)\n\n"
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
    
    private func renderPDF(title: String, body: String, note: Note, branded: Bool) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let margin: CGFloat = 40
        let headerHeight: CGFloat = branded ? 88 : 0
        let footerHeight: CGFloat = branded ? 36 : 0
        let contentTop = margin + headerHeight
        let contentHeight = pageRect.height - contentTop - margin - footerHeight
        
        let titleFont = UIFont.boldSystemFont(ofSize: branded ? 20 : 18)
        let metaFont = UIFont.systemFont(ofSize: 10)
        let bodyFont = UIFont.systemFont(ofSize: 11)
        let footerFont = UIFont.systemFont(ofSize: 9)
        
        let navy = UIColor(red: 0.078, green: 0.137, blue: 0.239, alpha: 1)
        let orange = UIColor(red: 0.961, green: 0.416, blue: 0.039, alpha: 1)
        let secondary = UIColor(red: 0.302, green: 0.376, blue: 0.482, alpha: 1)
        
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.paragraphSpacing = 6
        
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: navy,
            .paragraphStyle: paragraph
        ]
        
        return renderer.pdfData { context in
            context.beginPage()
            
            if branded {
                navy.setFill()
                UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageRect.width, height: 64)).fill()
                orange.setFill()
                UIBezierPath(rect: CGRect(x: 0, y: 64, width: pageRect.width, height: 3)).fill()
                
                if let logo = UIImage(named: "LaunchLogo") {
                    let logoSide: CGFloat = 36
                    logo.draw(in: CGRect(x: margin, y: 14, width: logoSide, height: logoSide))
                }
                
                let brandAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: UIColor.white
                ]
                "Paperorg Notes".draw(at: CGPoint(x: margin + 44, y: 18), withAttributes: brandAttrs)
                
                let subtitleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.85)
                ]
                "Pro export".draw(at: CGPoint(x: margin + 44, y: 38), withAttributes: subtitleAttrs)
            }
            
            var y = contentTop
            title.draw(
                at: CGPoint(x: margin, y: y),
                withAttributes: [.font: titleFont, .foregroundColor: navy]
            )
            y += 28
            
            let meta = "\(formattedDate(note.createdAt)) · \(note.appLanguage.displayName)"
            meta.draw(
                at: CGPoint(x: margin, y: y),
                withAttributes: [.font: metaFont, .foregroundColor: secondary]
            )
            y += 22
            
            let textRect = CGRect(x: margin, y: y, width: pageRect.width - margin * 2, height: contentHeight - (y - contentTop))
            body.draw(in: textRect, withAttributes: bodyAttrs)
            
            if branded {
                let footer = "Generated by Paperorg Notes · paperorg.com"
                let footerSize = footer.size(withAttributes: [.font: footerFont])
                footer.draw(
                    at: CGPoint(x: margin, y: pageRect.height - margin - footerSize.height + 8),
                    withAttributes: [.font: footerFont, .foregroundColor: secondary]
                )
            }
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
