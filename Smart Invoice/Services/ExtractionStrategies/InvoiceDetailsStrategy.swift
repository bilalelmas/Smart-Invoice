import Foundation

/// Fatura detaylarını (No, Tarih, ETTN) çıkarma stratejisi
/// Zone B (Header Right) bölgesini analiz eder
class InvoiceDetailsStrategy: InvoiceExtractionStrategy {
    
    func extract(context: ExtractionContext, invoice: inout Invoice) {
        // 1. İlgili blok ve satırları filtrele (Zone B: Header Right)
        let headerRightBlocks = SpatialEngine.blocks(in: .headerRight, from: context.blocks)
        let headerRightLines = SpatialEngine.lines(in: .headerRight, from: context.lines)
        
        // 2. Fatura Numarası
        invoice.invoiceNo = extractInvoiceNumber(blocks: headerRightBlocks, lines: headerRightLines) ?? extractInvoiceNumberFallback(from: context.rawText)
        
        // 3. Fatura Tarihi
        invoice.invoiceDate = extractDate(blocks: headerRightBlocks, lines: headerRightLines) ?? extractDateFallback(from: context.cleanLines)
        
        // 4. ETTN
        invoice.ettn = extractETTN(blocks: headerRightBlocks, lines: headerRightLines) ?? extractETTNFallback(from: context.rawText)
    }
    
    // MARK: - Private Methods
    
    private func extractInvoiceNumber(blocks: [TextBlock], lines: [TextLine]) -> String? {
        // Önce satırlarda ara
        for line in lines {
            let upper = line.text.uppercased()
            if upper.contains("FATURA NO") || upper.contains("FATURA NUMARASI") {
                // Standart format
                if let num = InvoiceParserHelper.extractString(from: line.text, pattern: RegexPatterns.InvoiceNo.standard) {
                    return num
                }
                // A101 format
                if let num = InvoiceParserHelper.extractString(from: line.text, pattern: RegexPatterns.InvoiceNo.a101) {
                    return num
                }
            }
            
            // Etiketsiz arama
            if let num = InvoiceParserHelper.extractString(from: line.text, pattern: RegexPatterns.InvoiceNo.standard) {
                return num
            }
        }
        
        // Fallback: Bloklarda ara
        for block in blocks {
            if let num = InvoiceParserHelper.extractString(from: block.text, pattern: RegexPatterns.InvoiceNo.standard) {
                return num
            }
        }
        
        return nil
    }
    
    private func extractInvoiceNumberFallback(from text: String) -> String {
        // Genel Tarama (eski yöntemden)
        if let num = InvoiceParserHelper.extractString(from: text, pattern: RegexPatterns.InvoiceNo.standard) { return num }
        return ""
    }
    
    private func extractDate(blocks: [TextBlock], lines: [TextLine]) -> Date? {
        let datePattern = RegexPatterns.DateFormat.standard
        
        // Önce etiketli satırlarda ara
        for line in lines {
            let upper = line.text.uppercased()
            if RegexPatterns.Keywords.dateTargets.contains(where: { upper.contains($0) }) &&
               !RegexPatterns.Keywords.dateBlacklist.contains(where: { upper.contains($0) }) {
                for block in line.blocks {
                    if let dateStr = InvoiceParserHelper.extractString(from: block.text, pattern: datePattern) {
                        return InvoiceParserHelper.parseDateString(dateStr)
                    }
                }
                if let dateStr = InvoiceParserHelper.extractString(from: line.text, pattern: datePattern) {
                    return InvoiceParserHelper.parseDateString(dateStr)
                }
            }
        }
        
        // Genel arama (ilk 10 satır)
        for line in lines.prefix(10) {
            let upper = line.text.uppercased()
            if RegexPatterns.Keywords.dateBlacklist.contains(where: { upper.contains($0) }) { continue }
            
            for block in line.blocks {
                if let dateStr = InvoiceParserHelper.extractString(from: block.text, pattern: datePattern) {
                    return InvoiceParserHelper.parseDateString(dateStr)
                }
            }
        }
        
        return nil
    }
    
    private func extractDateFallback(from cleanLines: [String]) -> Date {
        // Genel Arama (Header bölgesinde)
        let limit = min(cleanLines.count, 20)
        for i in 0..<limit {
            let line = cleanLines[i]
            if RegexPatterns.Keywords.dateBlacklist.contains(where: { line.uppercased().contains($0) }) { continue }
            
            if let d = InvoiceParserHelper.extractString(from: line, pattern: RegexPatterns.DateFormat.standard) {
                return InvoiceParserHelper.parseDateString(d)
            }
        }
        return Date()
    }
    
    private func extractETTN(blocks: [TextBlock], lines: [TextLine]) -> String? {
        // Önce etiketli satırlarda ara
        for line in lines {
            let upper = line.text.uppercased()
            if upper.contains("ETTN") {
                if let ettnIndex = upper.range(of: "ETTN") {
                    let afterETTN = String(line.text[ettnIndex.upperBound...])
                    let ettn = InvoiceParserHelper.extractETTNFromText(afterETTN)
                    if !ettn.isEmpty {
                        return ettn
                    }
                }
            }
        }
        
        // Genel arama
        let allText = blocks.map { $0.text }.joined(separator: " ")
        let ettn = InvoiceParserHelper.extractETTNFromText(allText)
        return ettn.isEmpty ? nil : ettn
    }
    
    private func extractETTNFallback(from rawText: String) -> String {
        return InvoiceParserHelper.extractETTNFromText(rawText)
    }
}
