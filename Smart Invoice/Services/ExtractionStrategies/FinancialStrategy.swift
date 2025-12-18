import Foundation
import CoreGraphics

/// Finansal verileri (Toplam, Matrah, KDV) çıkarma stratejisi
/// Zone D (Footer) bölgesini analiz eder ve validasyon sağlar
class FinancialStrategy: InvoiceExtractionStrategy {
    
    func extract(context: ExtractionContext, invoice: inout Invoice) {
        var extractionConfidence: Double = 0.0
        
        // 0. Spatial Priority (Öncelikli Konumsal Analiz)
        if let profile = context.profile, let priorityRect = profile.amountCoordinates {
            let priorityBlocks = context.blocks.filter { block in
                let intersection = block.frame.intersection(priorityRect)
                // Blok alanının %50'sinden fazlası hedef bölgedeyse kabul et
                return (intersection.width * intersection.height) > (block.frame.width * block.frame.height * 0.5)
            }
            
            if !priorityBlocks.isEmpty {
                // Öncelikli bölgede tutar ara
                let priorityText = priorityBlocks.map { $0.text }.joined(separator: "\n")
                let amounts = InvoiceParserHelper.extractAllAmounts(from: priorityText)
                if let maxAmount = amounts.max(), maxAmount > 0 {
                    print("🎯 Spatial Priority ile Tutar Bulundu: \(maxAmount) (Profil: \(profile.vendorName))")
                    invoice.totalAmount = maxAmount
                    extractionConfidence = 0.95 // Çok yüksek güven
                    
                    // Diğer değerleri tahmin etmeye çalış (geriye doğru hesaplama)
                    let taxRate = extractTaxRate(from: priorityText) > 0 ? extractTaxRate(from: priorityText) : 0.18 // Varsayılan %18
                    invoice.subTotal = maxAmount / (1 + taxRate)
                    invoice.taxAmount = maxAmount - invoice.subTotal
                }
            }
        }
        
        // Eğer Spatial Priority ile bulunamadıysa standart akışa devam et
        if invoice.totalAmount == 0 {
            if !context.blocks.isEmpty {
                // Zone D (Footer): Finansal Veriler
                let footerLines = SpatialEngine.lines(in: .footer, from: context.lines)
                
                // KDV oranını tespit et
                let footerText = footerLines.map { $0.text }.joined(separator: " ")
                let taxRate = extractTaxRate(from: footerText)
                
                let vendorType = invoice.metadata["vendor_type"] ?? "Generic_E-Arsiv"
                invoice.totalAmount = extractTotalAmountFromZone(lines: footerLines, vendorType: vendorType)
                
                if invoice.totalAmount > 0 {
                    // Güven Skoru Hesaplama
                    let anchors = ["ÖDENECEK TUTAR", "VERGİLER DAHİL TOPLAM", "GENEL TOPLAM"]
                    let footerStr = footerLines.map { $0.text.uppercased() }.joined(separator: "\n")
                    
                    // 1. Regex/Format Skoru (Zaten bulunduysa +0.2)
                    extractionConfidence = 0.60 + 0.20
                    
                    // 2. Çapa Kelime Skoru
                    if anchors.contains(where: { footerStr.contains($0) }) {
                        extractionConfidence += 0.40
                    }
                    
                    // 3. Konumsal Skor (Footer'da olduğu için zaten +0.4 sayılabilir ama daha spesifik olalım)
                    // Eğer son satırlardaysa
                    if let lastLine = footerLines.last, lastLine.text.contains(String(format: "%.2f", invoice.totalAmount).replacingOccurrences(of: ".", with: ",")) {
                        extractionConfidence += 0.40 // Sağ alt köşedeyse (tahmini)
                    }
                    
                    // Maksimum 1.0
                    extractionConfidence = min(extractionConfidence, 1.0)
                    
                    invoice.subTotal = extractSubTotalFromZone(lines: footerLines, totalAmount: invoice.totalAmount, taxRate: taxRate)
                    invoice.taxAmount = extractTaxAmountFromZone(lines: footerLines, subTotal: invoice.subTotal, taxRate: taxRate)
                }
            }
            
            // Hala bulunamadıysa Fallback
            if invoice.totalAmount == 0 {
                // Fallback (text-based)
                let taxRate = extractTaxRate(from: context.rawText)
                invoice.totalAmount = extractTotalAmountFallback(from: context.rawText)
                
                if invoice.totalAmount > 0 {
                     extractionConfidence = 0.50 // Fallback düşük güven
                     invoice.subTotal = extractSubTotalFallback(from: context.rawText, totalAmount: invoice.totalAmount, taxRate: taxRate)
                     invoice.taxAmount = extractTaxAmountFallback(from: context.rawText, taxRate: taxRate)
                }
            }
        }
        
        // Self-Healing: Matematiksel sağlama ile eksik verileri tamamla
        var financialValidation = SpatialEngine.FinancialValidation(
            totalAmount: invoice.totalAmount,
            taxAmount: invoice.taxAmount,
            subTotal: invoice.subTotal
        )
        financialValidation.heal()
        
        // Eğer heal işlemi bir şeyleri düzelttiyse güveni biraz artır
        if invoice.totalAmount == 0 && financialValidation.totalAmount > 0 {
             extractionConfidence += 0.1
        }
        
        invoice.totalAmount = financialValidation.totalAmount
        invoice.taxAmount = financialValidation.taxAmount
        invoice.subTotal = financialValidation.subTotal
        
        // Ek validasyon
        validateAndFixAmounts(&invoice)
        
        // Güven Skorunu Kaydet
        invoice.confidenceScores["totalAmount"] = extractionConfidence
    }
    
    // MARK: - Private Methods (Zone-Based)
    
    // MARK: - Private Methods (Advanced Extraction)
    
    private func extractTaxRate(from text: String) -> Double {
        return InvoiceParserHelper.detectTaxRate(from: text)
    }
    
    /// Gelişmiş Tutar Çıkarma Mantığı (Anchor + Spatial Lookahead + Heuristic)
    private func extractTotalAmountFromZone(lines: [TextLine], vendorType: String) -> Double {
        
        // --- 1. Trendyol Direct (Özel Logic) ---
        if vendorType == "Trendyol_Direct" {
            // Y > 0.7 (Sayfanın alt kısmı)
            let bottomLines = lines.filter { $0.frame.minY > 0.7 }
            
            for line in bottomLines {
                let upper = line.text.uppercased()
                
                // İstenmeyen kelimeleri ele
                if upper.contains("TOPLAM BİRİM FİYAT") { continue }
                
                // Hedef: "Vergiler Dahil Toplam Tutar"
                if upper.contains("VERGİLER DAHİL TOPLAM") {
                     // Bounding box'ın sağındaki değeri al (Basitçe satırdaki son değer)
                     let amounts = InvoiceParserHelper.extractAllAmounts(from: line.text)
                     if let rightMost = amounts.last, rightMost > 0 {
                         return rightMost
                     }
                }
            }
            // Bulunamazsa Generic metoda düşebilir veya 0 dönebilir
            // Fallback olarak Generic logic'i çalıştıralım:
        }
        
        // --- 2. Generic E-Arşiv (Bottom-up Logic) ---
        // İstenen Mantık: 'Ödenecek Tutar' veya 'Vergiler Dahil Toplam Tutar' görünce DUR ve en sağdakini al.
        let strictAnchors = ["ÖDENECEK TUTAR", "VERGİLER DAHİL TOPLAM", "GENEL TOPLAM", "TOPLAM TUTAR"]
        
        for line in lines.reversed() {
            let upper = line.text.uppercased()
            
            // Kara liste kontrolü (KDV hariç, vb.)
            if RegexPatterns.Keywords.amountBlacklist.contains(where: { upper.contains($0) }) { continue }
            
            // 1. Strict Anchor Kontrolü
            if strictAnchors.contains(where: { upper.contains($0) }) {
                // Çapa bulundu! Hemen sayıları çek.
                let amounts = InvoiceParserHelper.extractAllAmounts(from: line.text)
                if let rightMost = amounts.last, rightMost > 0 {
                    return rightMost // BULDUK VE DURDUK
                }
            }
            
            // 2. Yedek "TOPLAM" Kontrolü
            // "TOPLAM KDV" veya "ARA TOPLAM" değilse ve içinde "TOPLAM" geçiyorsa
            if upper.contains("TOPLAM") && !upper.contains("KDV") && !upper.contains("ARA") {
                let amounts = InvoiceParserHelper.extractAllAmounts(from: line.text)
                if let rightMost = amounts.last, rightMost > 0 {
                     return rightMost // Alttan başladığımız için ilk bulduğumuz "TOPLAM" en alttakidir.
                }
            }
        }
        
        // 3. Fallback: Çıplak Sayılar (Hala bulunamadıysa)
        for line in lines.reversed() {
            if line.text.uppercased().contains("ÖDENECEK") {
                let amounts = InvoiceParserHelper.extractAllAmounts(from: line.text)
                if let rightMost = amounts.last, rightMost > 0 { return rightMost }
            }
        }
        
        var allCandidates: [Double] = []
        for line in lines.reversed() {
             let amounts = InvoiceParserHelper.extractAllAmounts(from: line.text)
             allCandidates.append(contentsOf: amounts)
        }
        return allCandidates.max() ?? 0.0
    }
    
    private func extractSubTotalFromZone(lines: [TextLine], totalAmount: Double, taxRate: Double) -> Double {
        // Matrah (Ara Toplam) bulma
        // "TOPLAM KDV" veya "KDV" satırlarından önceki satırlar veya "MATRAH" kelimesi
        
        for line in lines.reversed() {
             let upper = line.text.uppercased()
             if RegexPatterns.Keywords.subTotalAmounts.contains(where: { upper.contains($0) }) {
                 if let amount = InvoiceParserHelper.extractAmount(from: line.text) {
                     // Matrah, toplamdan küçük olmalı
                     if totalAmount > 0 && amount < totalAmount {
                         return amount
                     }
                     // Eğer toplam yoksa, bulunanı döndür
                     if totalAmount == 0 { return amount }
                 }
             }
        }
        
        // Bulunamadıysa hesapla
        if totalAmount > 0 {
            return totalAmount / (1 + taxRate)
        }
        return 0.0
    }
    
    private func extractTaxAmountFromZone(lines: [TextLine], subTotal: Double, taxRate: Double) -> Double {
        for line in lines.reversed() {
             let upper = line.text.uppercased()
             // "TOPLAM KDV" veya sadece "KDV" ama "KDV HARİÇ" değil
             if RegexPatterns.Keywords.taxAmounts.contains(where: { upper.contains($0) }) {
                 if let amount = InvoiceParserHelper.extractAmount(from: line.text) {
                     // KDV validasyonu
                     if subTotal > 0 {
                         let expected = subTotal * taxRate
                         // Toleranslı kontrol (%10 hata payı)
                         if abs(amount - expected) < (expected * 0.1) {
                             return amount
                         }
                     } else {
                         return amount
                     }
                 }
             }
        }
        
        // Bulunamadıysa hesapla
        if subTotal > 0 {
            return subTotal * taxRate
        }
        return 0.0
    }
    
    // MARK: - Private Methods (Fallback)
    
    private func extractTotalAmountFallback(from text: String) -> Double {
        let lines = text.components(separatedBy: .newlines)
        
        // İstenen Mantık: Bottom-Up + Stop Immediately (Fallback için de geçerli)
        let strictAnchors = ["ÖDENECEK TUTAR", "VERGİLER DAHİL TOPLAM", "GENEL TOPLAM", "TOPLAM TUTAR"]
        
        for line in lines.reversed() {
            let upper = line.uppercased()
            
            // Kara liste (KDV Hariç vb.)
            if RegexPatterns.Keywords.amountBlacklist.contains(where: { upper.contains($0) }) { continue }
            
            // 1. Strict Anchor
            if strictAnchors.contains(where: { upper.contains($0) }) {
                 let amounts = InvoiceParserHelper.extractAllAmounts(from: line)
                 if let rightMost = amounts.last, rightMost > 0 {
                     return rightMost
                 }
            }
            
            // 2. Yedek "TOPLAM"
            if upper.contains("TOPLAM") && !upper.contains("KDV") && !upper.contains("ARA") {
                let amounts = InvoiceParserHelper.extractAllAmounts(from: line)
                if let rightMost = amounts.last, rightMost > 0 {
                    return rightMost
                }
            }
        }
        
        // 3. Hiçbiri yoksa -> Max Value (Son Çare)
        var candidates: [Double] = []
        for line in lines {
             let amounts = InvoiceParserHelper.extractAllAmounts(from: line)
             candidates.append(contentsOf: amounts)
        }
        return candidates.max() ?? 0.0
    }
    
    private func extractSubTotalFallback(from text: String, totalAmount: Double, taxRate: Double) -> Double {
        let lines = text.components(separatedBy: .newlines)
        var candidates: [Double] = []
        
        for line in lines.reversed() {
            let upper = line.uppercased()
            if RegexPatterns.Keywords.subTotalAmounts.contains(where: { upper.contains($0) }) {
                if let amount = InvoiceParserHelper.extractAmount(from: line) { candidates.append(amount) }
            }
        }
        
        let maxCandidate = candidates.max() ?? 0.0
        if totalAmount > 0 && maxCandidate > totalAmount {
             return totalAmount / (1 + taxRate)
        }
        return maxCandidate > 0 ? maxCandidate : (totalAmount > 0 ? totalAmount / (1 + taxRate) : 0.0)
    }
    
    private func extractTaxAmountFallback(from text: String, taxRate: Double) -> Double {
        let lines = text.components(separatedBy: .newlines)
        var candidates: [Double] = []
        
        for line in lines.reversed() {
             let upper = line.uppercased()
             if RegexPatterns.Keywords.taxAmounts.contains(where: { upper.contains($0) }) {
                 if let amount = InvoiceParserHelper.extractAmount(from: line) { candidates.append(amount) }
             }
        }
        
        let validCandidates = candidates.filter { $0 > 0 }
        return validCandidates.min() ?? 0.0
    }
    
    // MARK: - Validation
    
    private func validateAndFixAmounts(_ invoice: inout Invoice) {
        // 1. KDV tutarının matrahtan küçük olduğunu kontrol et
        if invoice.subTotal > 0 && invoice.taxAmount > 0 {
            let maxTaxRate = 0.20
            let expectedMaxTax = invoice.subTotal * maxTaxRate
            
            if invoice.taxAmount > expectedMaxTax {
                if invoice.totalAmount > 0 {
                    let calculatedTax = invoice.totalAmount - invoice.subTotal
                    if calculatedTax > 0 && calculatedTax <= expectedMaxTax {
                        invoice.taxAmount = calculatedTax
                    } else {
                        invoice.taxAmount = invoice.subTotal * 0.18
                    }
                } else {
                    invoice.taxAmount = invoice.subTotal * 0.18
                }
            }
        }
        
        // 2. Matrah + KDV ≈ Toplam kontrolü
        if invoice.subTotal > 0 && invoice.taxAmount > 0 && invoice.totalAmount > 0 {
            let calculatedTotal = invoice.subTotal + invoice.taxAmount
            let difference = abs(calculatedTotal - invoice.totalAmount)
            let percentage = (difference / invoice.totalAmount) * 100
            
            if percentage > 2.0 {
                let calculatedSubTotal = invoice.totalAmount - invoice.taxAmount
                if calculatedSubTotal > 0 {
                    invoice.subTotal = calculatedSubTotal
                }
            }
        }
        
        // 3. Eksik verileri tamamla
        if invoice.subTotal == 0 && invoice.totalAmount > 0 && invoice.taxAmount > 0 {
            invoice.subTotal = invoice.totalAmount - invoice.taxAmount
        }
        
        if invoice.taxAmount == 0 && invoice.totalAmount > 0 && invoice.subTotal > 0 {
            invoice.taxAmount = invoice.totalAmount - invoice.subTotal
        }
        
        if invoice.subTotal == 0 && invoice.totalAmount > 0 {
            invoice.subTotal = invoice.totalAmount / 1.18
            if invoice.taxAmount == 0 {
                invoice.taxAmount = invoice.totalAmount - invoice.subTotal
            }
        }
        
        // 4. KDV matrahtan büyükse düzelt
        if invoice.subTotal > 0 && invoice.taxAmount > invoice.subTotal {
            invoice.taxAmount = invoice.subTotal * 0.18
            if invoice.totalAmount == 0 {
                invoice.totalAmount = invoice.subTotal + invoice.taxAmount
            }
        }
    }
}
