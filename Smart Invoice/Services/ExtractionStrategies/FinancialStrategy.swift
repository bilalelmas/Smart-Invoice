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
                let amounts = InvoiceParserHelper.findAllAmountsInString(priorityText)
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
                
                invoice.totalAmount = extractTotalAmountFromZone(lines: footerLines)
                
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
        return InvoiceParserHelper.extractTaxRate(from: text)
    }
    
    /// Gelişmiş Tutar Çıkarma Mantığı (Anchor + Spatial Lookahead + Heuristic)
    private func extractTotalAmountFromZone(lines: [TextLine]) -> Double {
        var candidates: [Double] = []
        let anchors = ["ÖDENECEK TUTAR", "VERGİLER DAHİL TOPLAM", "GENEL TOPLAM", "TOPLAM TUTAR"]
        
        for line in lines.reversed() {
            let upper = line.text.uppercased()
            
            // 1. Anchor (Çapa) Kelime Kontrolü
            if anchors.contains(where: { upper.contains($0) }) {
                // Konumsal Filtre: Metnin sağında veya altında sayı ara
                // Önce satırın kendisinde sayı var mı?
                if let amount = InvoiceParserHelper.findAmountInString(line.text) {
                    candidates.append(amount)
                } else {
                    // Satırda yoksa, bu satırın hemen altındaki veya sağındaki bloklara bakmak gerekir
                    // SpatialEngine'de bu logic olmadığı için şimdilik satır bazlı devam ediyoruz
                    // İleride SpatialEngine.findBlockToRight(of: line) eklenebilir.
                }
            }
            
            // 2. Genel Arama (Eski Yöntem)
            if RegexPatterns.Keywords.amountBlacklist.contains(where: { upper.contains($0) }) { continue }
            // Sadece "TOPLAM" kelimesine güvenme, "ARA TOPLAM" da olabilir
            if upper.contains("TOPLAM") && !upper.contains("ARA") && !upper.contains("KDV") {
                if let amount = InvoiceParserHelper.findAmountInString(line.text) {
                    candidates.append(amount)
                }
            }
            
            // 3. Çıplak Sayılar
            if RegexPatterns.Keywords.payableAmounts.contains(where: { upper.contains($0) }) {
                if let amount = InvoiceParserHelper.findAmountInString(line.text) {
                    candidates.append(amount)
                }
            }
        }
        
        // Doğrulama (Heuristic): En büyük değer mi?
        let maxCandidate = candidates.max() ?? 0.0
        
        // Eğer aday 0 ise, tüm sayıları topla ve en büyüğü al (Son çare)
        if maxCandidate == 0.0 {
            let allText = lines.map { $0.text }.joined(separator: "\n")
            let allAmounts = InvoiceParserHelper.findAllAmountsInString(allText)
            return allAmounts.max() ?? 0.0
        }
        
        return maxCandidate
    }
    
    private func extractSubTotalFromZone(lines: [TextLine], totalAmount: Double, taxRate: Double) -> Double {
        // Matrah (Ara Toplam) bulma
        // "TOPLAM KDV" veya "KDV" satırlarından önceki satırlar veya "MATRAH" kelimesi
        
        for line in lines.reversed() {
             let upper = line.text.uppercased()
             if RegexPatterns.Keywords.subTotalAmounts.contains(where: { upper.contains($0) }) {
                 if let amount = InvoiceParserHelper.findAmountInString(line.text) {
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
                 if let amount = InvoiceParserHelper.findAmountInString(line.text) {
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
        var candidates: [Double] = []
        
        for line in lines.reversed() {
            let upper = line.uppercased()
            if RegexPatterns.Keywords.amountBlacklist.contains(where: { upper.contains($0) }) { continue }
            if RegexPatterns.Keywords.payableAmounts.contains(where: { upper.contains($0) }) {
                if let amount = InvoiceParserHelper.findAmountInString(line) { candidates.append(amount) }
            }
        }
        return candidates.max() ?? 0.0
    }
    
    private func extractSubTotalFallback(from text: String, totalAmount: Double, taxRate: Double) -> Double {
        let lines = text.components(separatedBy: .newlines)
        var candidates: [Double] = []
        
        for line in lines.reversed() {
            let upper = line.uppercased()
            if RegexPatterns.Keywords.subTotalAmounts.contains(where: { upper.contains($0) }) {
                if let amount = InvoiceParserHelper.findAmountInString(line) { candidates.append(amount) }
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
                 if let amount = InvoiceParserHelper.findAmountInString(line) { candidates.append(amount) }
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
