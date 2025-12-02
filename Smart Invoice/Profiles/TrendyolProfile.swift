import Foundation

/// Trendyol faturalarına özel iş mantığı.
/// Referans: Python projesi 'profile_trendyol.py'
struct TrendyolProfile: VendorProfile {
    var vendorName: String = "Trendyol"
    
    func applies(to textLowercased: String) -> Bool {
        // Python: ('trendyol' in text_lower) or ('trendyolmail' in text_lower)
        return textLowercased.contains("trendyol") || textLowercased.contains("trendyolmail")
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
