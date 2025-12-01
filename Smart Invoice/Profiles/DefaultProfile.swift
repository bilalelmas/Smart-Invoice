import Foundation
import CoreGraphics

/// Bilinmeyen satıcılar için varsayılan profil.
/// Default profile for unknown vendors.
struct DefaultProfile: VendorProfileProtocol {
    var vendorName: String { "Bilinmeyen Satıcı" }
    
    func isMatch(text: String) -> Bool {
        return true // Her zaman eşleşir (Fallback)
    }
    
    func parse(textBlocks: [TextBlock]) -> Invoice? {
        var invoice = Invoice()
        invoice.merchantName = nil // Kullanıcı girmeli
        
        let fullText = textBlocks.map { $0.text }.joined(separator: "\n")
        invoice.rawText = fullText
        
        // Genel Tarih Arama
        if let dateRange = fullText.range(of: #"\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression) {
            let dateString = String(fullText[dateRange])
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM.yyyy"
            invoice.date = formatter.date(from: dateString)
        }
        
        // Genel Tutar Arama (Örn: "Toplam: 100,00")
        // Bu çok basitleştirilmiş bir örnek.
        
        return invoice
    }
}
