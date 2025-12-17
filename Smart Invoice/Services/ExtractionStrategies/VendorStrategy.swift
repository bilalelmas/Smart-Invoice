import Foundation
import CoreGraphics

/// Satıcı bilgilerini (Ad, Vergi No) çıkarma stratejisi
/// Zone A (Header Left) bölgesini analiz eder
class VendorStrategy: InvoiceExtractionStrategy {
    
    func extract(context: ExtractionContext, invoice: inout Invoice) {
        // 1. İlgili blok ve satırları filtrele (Zone A: Header Left)
        let headerLeftBlocks = SpatialEngine.blocks(in: .headerLeft, from: context.blocks)
        let headerLeftLines = SpatialEngine.lines(in: .headerLeft, from: context.lines)
        
        let fullTextUpper = context.fullText.uppercased()
        
        // --- Öncelik 1: Bilinen VKN ile Doğrudan Tespit ---
        // DSM Grup VKN: 3130557669 -> Trendyol
        if fullTextUpper.contains("3130557669") {
            invoice.merchantName = "Trendyol (DSM Grup)"
            invoice.merchantTaxID = "3130557669"
            print("✅ VendorStrategy: VKN ile Trendyol tespit edildi.")
            
            // Eğer profil zaten Trendyol ise ismini ezmeyebiliriz ama garanti olsun
            return
        }
        
        // --- Öncelik 2: Satıcı Adını Çıkar ---
        let detectedName = extractMerchantName(blocks: headerLeftBlocks, lines: headerLeftLines)
        if !detectedName.isEmpty {
            invoice.merchantName = detectedName
        }
        
        // --- Öncelik 3: Vergi Numarasını Çıkar ---
        let detectedTaxID = extractMerchantTaxID(blocks: headerLeftBlocks, fullText: context.fullText)
        if !detectedTaxID.isEmpty {
            invoice.merchantTaxID = detectedTaxID
        }
        
        // --- Pazaryeri Kontrolü ---
        if fullTextUpper.contains("PAZARYERİ: TRENDYOL") || fullTextUpper.contains("ÖDEME ARACISI: TRENDYOL") {
            print("ℹ️ VendorStrategy: Trendyol Pazaryeri faturası.")
            invoice.metadata["source"] = "Trendyol_Marketplace"
        }
    }
    
    // MARK: - Private Methods
    
    /// Zone A (Header Left): Satıcı adını çıkarır
    private func extractMerchantName(blocks: [TextBlock], lines: [TextLine]) -> String {
        // Hedef: Belgenin en üstündeki ilk büyük/belirgin metin bloğu (Header)
        // Ancak "SAYIN", "MÜŞTERİ", "ALICI" gibi kelimeler içerenleri hariç tutacağız.
        
        let forbiddenKeywords = ["SAYIN", "MÜŞTERİ", "ALICI", "MUSTERI", "SAYIM"]
        
        // Önce satırlarda ara (Y koordinatına göre sıralı)
        let sortedLines = lines.sorted { $0.frame.minY < $1.frame.minY }
        
        for line in sortedLines {
            let upper = line.text.uppercased()
            
            // Yasaklı kelimeler kontrolü
            if forbiddenKeywords.contains(where: { upper.contains($0) }) { continue }
            if RegexPatterns.Keywords.merchantBlacklist.contains(where: { upper.contains($0) }) { continue }
            if InvoiceParserHelper.isPhoneNumber(line.text) { continue }
            
            // Şirket ünvanı veya güvenilir başlık bul
            if RegexPatterns.Keywords.companySuffixes.contains(where: { upper.contains($0) }) {
                return line.text
            }
            
            // Eğer suffix yok ama en tepedeyse ve yeterince uzunsa aday olabilir
            // (İlk %10'luk kısımda)
            if line.frame.minY < 0.15 && line.text.count > 3 && !InvoiceParserHelper.containsDate(line.text) {
                return line.text // Geçici aday
            }
        }
        
        return ""
    }
    
    /// Zone A (Header Left): Satıcı vergi numarasını çıkarır
    private func extractMerchantTaxID(blocks: [TextBlock], fullText: String) -> String {
        // Önce belirli etiketlerle ara
        let vknPattern = "(?:VKN|VERGİ\\s*NO|VERGI\\s*NO)\\s*[:\\.]?\\s*(\\d{10})"
        if let id = InvoiceParserHelper.extractString(from: fullText, pattern: vknPattern) {
            return id
        }
        
        // Bloklarda 10-11 haneli sayı ara
        for block in blocks {
            if !InvoiceParserHelper.isPhoneNumber(block.text) {
                 if let id = InvoiceParserHelper.extractString(from: block.text, pattern: "\\b\\d{10}\\b") {
                     return id
                 }
                // TCKN (11 hane)
                if let id = InvoiceParserHelper.extractString(from: block.text, pattern: "\\b\\d{11}\\b") {
                    return id
                }
            }
        }
        
        return ""
    }
}
