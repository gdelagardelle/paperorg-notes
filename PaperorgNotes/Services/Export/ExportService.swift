import Foundation
import PDFKit
import UIKit
import CoreText

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
    
    func exportPDF(note: Note, branding: ExportBranding?) throws -> URL {
        let content = buildPDFBody(note: note)
        let pdfData = renderPDF(title: note.title, body: content, note: note, branding: branding)
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

    private func buildPDFBody(note: Note) -> String {
        var parts: [String] = []

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
    
    private func renderPDF(title: String, body: String, note: Note, branding: ExportBranding?) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let margin: CGFloat = 40
        let footerHeight: CGFloat = branding == nil ? 0 : 28
        let fullHeaderHeight: CGFloat = branding == nil ? 0 : 88
        let compactHeaderHeight: CGFloat = branding == nil ? 0 : 28
        
        let titleFont = UIFont.boldSystemFont(ofSize: branding == nil ? 18 : 20)
        let metaFont = UIFont.systemFont(ofSize: 10)
        let bodyFont = UIFont.systemFont(ofSize: 11)
        let footerFont = UIFont.systemFont(ofSize: 9)
        
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.paragraphSpacing = 6
        
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: PDFBrandColors.navy,
            .paragraphStyle: paragraph
        ]
        let bodyString = NSAttributedString(string: body, attributes: bodyAttrs)
        
        return renderer.pdfData { context in
            var textStartIndex = 0
            var pageIndex = 0
            
            while textStartIndex < bodyString.length {
                context.beginPage()
                
                let headerHeight = pageIndex == 0 ? fullHeaderHeight : compactHeaderHeight
                if let branding {
                    if pageIndex == 0 {
                        drawFullHeader(branding: branding, pageRect: pageRect, margin: margin)
                    } else {
                        drawCompactHeader(branding: branding, pageRect: pageRect, margin: margin)
                    }
                }
                
                let contentTop = margin + headerHeight + (pageIndex == 0 ? 52 : 8)
                let contentBottom = pageRect.height - margin - footerHeight
                let textRect = CGRect(
                    x: margin,
                    y: contentTop,
                    width: pageRect.width - margin * 2,
                    height: max(0, contentBottom - contentTop)
                )
                
                if pageIndex == 0 {
                    var y = margin + headerHeight
                    title.draw(
                        at: CGPoint(x: margin, y: y),
                        withAttributes: [.font: titleFont, .foregroundColor: PDFBrandColors.navy]
                    )
                    y += 28
                    
                    let meta = "\(formattedDate(note.createdAt)) · \(note.appLanguage.displayName)"
                    meta.draw(
                        at: CGPoint(x: margin, y: y),
                        withAttributes: [.font: metaFont, .foregroundColor: PDFBrandColors.secondary]
                    )
                    y += 24
                    
                    let adjustedRect = CGRect(
                        x: textRect.origin.x,
                        y: y,
                        width: textRect.width,
                        height: max(0, textRect.maxY - y)
                    )
                    textStartIndex = drawTextPage(
                        bodyString,
                        startingAt: textStartIndex,
                        in: adjustedRect,
                        context: context.cgContext
                    )
                } else {
                    textStartIndex = drawTextPage(
                        bodyString,
                        startingAt: textStartIndex,
                        in: textRect,
                        context: context.cgContext
                    )
                }
                
                if let branding {
                    let footer = branding.footerText
                    footer.draw(
                        at: CGPoint(x: margin, y: pageRect.height - margin - 6),
                        withAttributes: [.font: footerFont, .foregroundColor: PDFBrandColors.secondary]
                    )
                }
                
                pageIndex += 1
                if pageIndex > 200 { break }
            }
        }
    }
    
    private func drawFullHeader(branding: ExportBranding, pageRect: CGRect, margin: CGFloat) {
        PDFBrandColors.navy.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageRect.width, height: 64)).fill()
        PDFBrandColors.orange.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 64, width: pageRect.width, height: 3)).fill()
        
        var textX = margin
        if let logo = branding.logo {
            let logoSide: CGFloat = 36
            drawLogo(logo, in: CGRect(x: margin, y: 14, width: logoSide, height: logoSide))
            textX = margin + logoSide + 8
        }
        
        let brandAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 14),
            .foregroundColor: UIColor.white
        ]
        branding.brandName.draw(at: CGPoint(x: textX, y: 18), withAttributes: brandAttrs)
        
        if !branding.brandSubtitle.isEmpty {
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            branding.brandSubtitle.draw(at: CGPoint(x: textX, y: 38), withAttributes: subtitleAttrs)
        }
    }
    
    private func drawCompactHeader(branding: ExportBranding, pageRect: CGRect, margin: CGFloat) {
        PDFBrandColors.orange.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: 18, width: pageRect.width - margin * 2, height: 1)).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: PDFBrandColors.secondary
        ]
        branding.brandName.draw(at: CGPoint(x: margin, y: 4), withAttributes: attrs)
    }
    
    private func drawLogo(_ logo: UIImage, in rect: CGRect) {
        let aspect = logo.size.width / max(logo.size.height, 1)
        var drawRect = rect
        if aspect > 1 {
            let height = rect.width / aspect
            drawRect = CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        } else {
            let width = rect.height * aspect
            drawRect = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
        }
        logo.draw(in: drawRect)
    }
    
    private func drawTextPage(
        _ text: NSAttributedString,
        startingAt location: Int,
        in rect: CGRect,
        context: CGContext
    ) -> Int {
        guard rect.height > 0, location < text.length else { return text.length }
        
        let range = CFRange(location: location, length: text.length - location)
        let path = CGPath(rect: rect, transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
        CTFrameDraw(frame, context)
        
        let visible = CTFrameGetVisibleStringRange(frame)
        return location + visible.length
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

private enum PDFBrandColors {
    static let navy = UIColor(red: 0.078, green: 0.137, blue: 0.239, alpha: 1)
    static let orange = UIColor(red: 0.961, green: 0.416, blue: 0.039, alpha: 1)
    static let secondary = UIColor(red: 0.302, green: 0.376, blue: 0.482, alpha: 1)
}
