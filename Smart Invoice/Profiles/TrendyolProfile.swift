import Foundation

/// Trendyol faturalarına özel iş mantığı.
/// Referans: Python projesi 'profile_trendyol.py'
struct TrendyolProfile: VendorProfile {
    var vendorName: String = "Trendyol"
    
    func applies(to textLowercased: String) -> Bool {
        // Sadece "trendyol" kelimesi geçmesi yetmez, fatura başlığında veya mail adresinde arayalım.
        // Eski kod çok agresifti.
        
        let isTrendyolVendor = textLowercased.contains("dsm grup") || textLowercased.contains("trendyol")
        
        // Eğer metin çok kısaysa (hatalı okuma) false dön
        if textLowercased.count < 50 { return false }
        
        return isTrendyolVendor
    }
    
    func applyRules(to invoice: inout Invoice, rawText: String) {
        // Trendyol faturalarında bazen "Sipariş No" fatura no yerine geçebilir veya ekstra bilgi olabilir.
        // Python kodundaki Regex: (?:SİPARİŞ|SIPARIS|ORDER)\s*(?:NO|NUMARASI)?\s*[:\-]?\s*([A-Z0-9\-]{6,25})
        
        let pattern = "(?:SİPARİŞ|SIPARIS|ORDER)\\s*(?:NO|NUMARASI)?\\s*[:\\-]?\\s*([A-Z0-9\\-]{6,25})"
        
        if let orderNo = InvoiceParser.shared.extractString(from: rawText, pattern: pattern) {
            // Eğer Fatura No bulunamadıysa veya boşsa, Sipariş No'yu yedek olarak kullanabiliriz
            // Veya Invoice modeline 'orderNumber' alanı ekleyip oraya yazabiliriz.
            if invoice.invoiceNo.isEmpty {
                invoice.invoiceNo = orderNo
            }
        }
        
        // Satıcı adını sabitle (OCR bazen yanlış okuyabilir)
        invoice.merchantName = "DSM Grup Danışmanlık (Trendyol)"
    }
}
