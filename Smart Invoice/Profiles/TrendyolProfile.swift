import Foundation
import CoreGraphics

/// Trendyol faturaları için ayrıştırma profili.
/// Parsing profile for Trendyol invoices.
struct TrendyolProfile: VendorProfileProtocol {
    var vendorName: String { "Trendyol" }
    
    func isMatch(text: String) -> Bool {
        return text.localizedCaseInsensitiveContains("Trendyol") || 
               text.localizedCaseInsensitiveContains("DSM Grup")
    }
    
    func parse(textBlocks: [TextBlock]) -> Invoice? {
        var invoice = Invoice()
        invoice.merchantName = vendorName
        
        // Ham metni birleştir
        let fullText = textBlocks.map { $0.text }.joined(separator: "\n")
        invoice.rawText = fullText
        
        // TODO: Detaylı Regex ve Spatial Analysis buraya eklenecek.
        // Şimdilik basit örnekler:
        
        // Tarih bulma (Örn: 01.01.2024)
        if let dateRange = fullText.range(of: #"\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression) {
            let dateString = String(fullText[dateRange])
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM.yyyy"
            invoice.date = formatter.date(from: dateString)
        }
        
        // Tutar bulma (Basit yaklaşım - en büyük sayıyı bulmaya çalışabiliriz veya "Toplam" kelimesini arayabiliriz)
        // Bu kısım Spatial Analysis ile daha sağlam yapılacak.
        
        return invoice
    }
}
