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
        // 1. Önce satırlarda etiketli arama
        for line in lines {
            let upper = line.text.uppercased()
            if upper.contains("FATURA NO") || upper.contains("FATURA NUMARASI") {
                if let num = InvoiceParserHelper.extractInvoiceNo(from: line.text) {
                    return num
                }
            }
        }
        
        // 2. Etiketsiz genel arama (Tüm Header bloğunda)
        for block in blocks {
            if let num = InvoiceParserHelper.extractInvoiceNo(from: block.text) {
                return num
            }
        }
        
        return nil
    }
    
    private func extractInvoiceNumberFallback(from text: String) -> String {
        return InvoiceParserHelper.extractInvoiceNo(from: text) ?? ""
    }
    

    
    private func extractDate(blocks: [TextBlock], lines: [TextLine]) -> Date? {
        // Önce etiketli satırlarda ara
        for line in lines {
            let upper = line.text.uppercased()
            if RegexPatterns.Keywords.dateTargets.contains(where: { upper.contains($0) }) &&
               !RegexPatterns.Keywords.dateBlacklist.contains(where: { upper.contains($0) }) {
                for block in line.blocks {
                    if let date = InvoiceParserHelper.extractDate(from: block.text) {
                        return date
                    }
                }
                if let date = InvoiceParserHelper.extractDate(from: line.text) {
                    return date
                }
            }
        }
        
        // Genel arama (ilk 10 satır)
        for line in lines.prefix(10) {
            let upper = line.text.uppercased()
            if RegexPatterns.Keywords.dateBlacklist.contains(where: { upper.contains($0) }) { continue }
            
            for block in line.blocks {
                if let date = InvoiceParserHelper.extractDate(from: block.text) {
                    return date
                }
            }
        }
        
        return nil
    }
    
    private func extractDateFallback(from cleanLines: [String]) -> Date {
        let limit = min(cleanLines.count, 20)
        for i in 0..<limit {
            let line = cleanLines[i]
            if RegexPatterns.Keywords.dateBlacklist.contains(where: { line.uppercased().contains($0) }) { continue }
            
            if let date = InvoiceParserHelper.extractDate(from: line) {
                return date
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
                    let ettn = InvoiceParserHelper.extractETTN(from: afterETTN)
                    if !ettn.isEmpty {
                        return ettn
                    }
                }
            }
        }
        
        // Genel arama
        let allText = blocks.map { $0.text }.joined(separator: " ")
        let ettn = InvoiceParserHelper.extractETTN(from: allText)
        return ettn.isEmpty ? nil : ettn
    }
    
    private func extractETTNFallback(from rawText: String) -> String {
        return InvoiceParserHelper.extractETTN(from: rawText)
    }
}
