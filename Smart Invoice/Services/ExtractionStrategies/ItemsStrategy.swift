import Foundation
import CoreGraphics

/// Ürün kalemlerini (Line Items) çıkarma stratejisi
/// Zone C (Body) bölgesini ve sütun yapısını analiz eder
class ItemsStrategy: InvoiceExtractionStrategy {
    
    func extract(context: ExtractionContext, invoice: inout Invoice) {
        if !context.blocks.isEmpty {
            let bodyLines = SpatialEngine.lines(in: .body, from: context.lines)
            invoice.items = extractLineItemsSpatialWithColumns(lines: bodyLines, allBlocks: context.blocks)
        } else {
            // Fallback (text-based)
            invoice.items = extractLineItemsFallback(from: context.cleanLines)
        }
    }
    
    // MARK: - Private Methods
    
    private func extractLineItemsSpatialWithColumns(lines: [TextLine], allBlocks: [TextBlock]) -> [InvoiceItem] {
        var items: [InvoiceItem] = []
        
        // 1. Sütunları tespit et
        let columns = SpatialEngine.detectColumns(in: lines)
        
        // 2. Tablo başlığını bul
        guard let headerIndex = lines.firstIndex(where: { line in
            RegexPatterns.Keywords.tableHeaders.contains(where: { line.text.uppercased().contains($0) })
        }) else {
            // Tablo başlığı yoksa, sütun tespiti ile devam et
            return extractItemsWithColumnDetection(lines: lines, columns: columns)
        }
        
        // 3. Tablo bitişini bul
        let footerIndex = lines.indices.first(where: { index in
            index > headerIndex && RegexPatterns.Keywords.tableFooters.contains(where: { lines[index].text.uppercased().contains($0) })
        }) ?? lines.count
        
        // 4. Satırları işle
        for i in (headerIndex + 1)..<footerIndex {
            let line = lines[i]
            if line.blocks.isEmpty { continue }
            
            // Sütun tespiti varsa, sütunlara göre parse et
            if !columns.isEmpty {
                if let item = extractItemFromLineWithColumns(line: line, columns: columns) {
                    items.append(item)
                }
            } else {
                // Fallback: Eski yöntem (en sağdaki blok fiyat)
                if let lastBlock = line.blocks.last, let amount = InvoiceParserHelper.findAmountInString(lastBlock.text) {
                    let nameBlocks = line.blocks.dropLast()
                    let name = nameBlocks.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        items.append(InvoiceItem(name: name, quantity: 1, unitPrice: amount, total: amount, taxRate: 18))
                    }
                }
            }
        }
        
        return items
    }
    
    private func extractItemsWithColumnDetection(lines: [TextLine], columns: [CGFloat]) -> [InvoiceItem] {
        var items: [InvoiceItem] = []
        
        for line in lines {
            if line.blocks.count < 2 { continue } // En az 2 blok olmalı
            
            // En sağdaki sütunda fiyat ara
            if let lastBlock = line.blocks.last,
               SpatialEngine.columnIndex(for: lastBlock, columns: columns) == columns.count - 1 {
                if let amount = InvoiceParserHelper.findAmountInString(lastBlock.text) {
                    let nameBlocks = line.blocks.dropLast()
                    let name = nameBlocks.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        items.append(InvoiceItem(name: name, quantity: 1, unitPrice: amount, total: amount, taxRate: 18))
                    }
                }
            }
        }
        return items
    }
    
    private func extractItemFromLineWithColumns(line: TextLine, columns: [CGFloat]) -> InvoiceItem? {
        guard line.blocks.count >= 2 else { return nil }
        
        // En sağdaki sütunda fiyat ara
        if let lastBlock = line.blocks.last,
           let columnIndex = SpatialEngine.columnIndex(for: lastBlock, columns: columns),
           columnIndex == columns.count - 1 {
            if let amount = InvoiceParserHelper.findAmountInString(lastBlock.text) {
                let nameBlocks = line.blocks.dropLast()
                let name = nameBlocks.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    return InvoiceItem(name: name, quantity: 1, unitPrice: amount, total: amount, taxRate: 18)
                }
            }
        }
        
        return nil
    }
    
    private func extractLineItemsFallback(from lines: [String]) -> [InvoiceItem] {
        var items: [InvoiceItem] = []
        
        guard let headerIndex = lines.firstIndex(where: { line in
            RegexPatterns.Keywords.tableHeaders.contains(where: { line.uppercased().contains($0) })
        }) else { return [] }
        
        let footerIndex = lines.indices.first(where: { index in
            index > headerIndex && RegexPatterns.Keywords.tableFooters.contains(where: { lines[index].uppercased().contains($0) })
        }) ?? lines.count
        
        for line in lines[(headerIndex + 1)..<footerIndex] {
            if line.count < 5 { continue }
            
            if let amountMatch = InvoiceParserHelper.extractLastMatch(from: line, pattern: RegexPatterns.Amount.flexible) {
                if amountMatch.count == 4 && amountMatch.starts(with: "202") { continue }
                
                let amount = InvoiceParserHelper.normalizeAmount(amountMatch)
                let name = line.replacingOccurrences(of: RegexPatterns.Amount.flexible, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "TL", with: "")
                    .replacingOccurrences(of: "Adet", with: "")
                
                if !name.isEmpty && amount > 0 {
                    items.append(InvoiceItem(name: name, quantity: 1, unitPrice: amount, total: amount, taxRate: 18))
                }
            }
        }
        return items
    }
}
