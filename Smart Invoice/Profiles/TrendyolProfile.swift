import Foundation
import CoreGraphics

/// Trendyol faturalarına özel iş mantığı.
/// Referans: Python projesi 'profile_trendyol.py'
struct TrendyolProfile: VendorProfile {
    var vendorName: String = "Trendyol"
    
    var vendorKeywords: [String] { ["DSM GRUP", "TRENDYOL", "BİLGİSAYAR SİSTEMLERİ", "DOLAP"] }
    // Trendyol faturaları A4 olduğu için alt kısım geniştir, varsayılan footer logic yeterli.
    
    func applies(to textLowercased: String) -> Bool {
        // Sadece "trendyol" kelimesi geçmesi yetmez, fatura başlığında veya mail adresinde arayalım.
        // Eski kod çok agresifti.
        
        let isTrendyolVendor = textLowercased.contains("dsm grup") || textLowercased.contains("trendyol")
        
        // Eğer metin çok kısaysa (hatalı okuma) false dön
        if textLowercased.count < 50 { return false }
        
        return isTrendyolVendor
    }
    
    func applyRules(to invoice: inout Invoice, rawText: String, blocks: [TextBlock]) {
        // 1. Satıcı Tipi Belirleme (Metadata)
        if rawText.contains("3130557669") {
            invoice.merchantName = "Trendyol (DSM Grup)"
            invoice.metadata["vendor_type"] = "Trendyol_Direct"
            
            // Trendyol Direct Faturası ise özel etiketleri ara
            if let amount = InvoiceParserHelper.extractAmount(from: rawText) {
                 invoice.totalAmount = amount
            }
        } else {
            // Trendyol Pazaryeri ise (Mavi, Junglee vb.)
            invoice.metadata["vendor_type"] = "Trendyol_Marketplace"
            
            // Standart e-arşiv etiketlerini ara
            if let amount = InvoiceParserHelper.extractAmount(from: rawText) {
                invoice.totalAmount = amount
            }
        }
        
        // 2. ETTN Ayıklama (Her iki tipte de standarttır)
        let ettn = InvoiceParserHelper.extractETTN(from: rawText)
        if !ettn.isEmpty {
            invoice.ettn = ettn
        }
        
        // 3. Spatial Logic (Apple Vision) - Sağ Alt Çeyrek Analizi
        if !blocks.isEmpty {
            let candidates = blocks.filter { block in
                // Sağ alt çeyrek: x > 0.6 ve y > 0.7
                return block.frame.minX > 0.6 && block.frame.minY > 0.7
            }.compactMap { block -> Double? in
                return InvoiceParserHelper.extractAmount(from: block.text)
            }
            
            // En sonuncusunu 'Toplam Tutar' olarak seç
            if let spatialTotal = candidates.last, spatialTotal > 0 {
                invoice.totalAmount = spatialTotal
                print("🎯 TrendyolProfile: Spatial Logic ile tutar güncellendi: \(spatialTotal)")
            }
        }
    }
}
