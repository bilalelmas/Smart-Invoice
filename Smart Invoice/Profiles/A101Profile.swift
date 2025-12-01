import Foundation

/// A101 faturaları için ayrıştırma profili.
struct A101Profile: VendorProfile {
    var vendorName: String { "A101" }
    
    func applies(to textLowercased: String) -> Bool {
        return textLowercased.contains("a101") || textLowercased.contains("yeni mağazacılık")
    }
    
    func applyRules(to invoice: inout Invoice, rawText: String) {
        invoice.merchantName = vendorName
        
        // A101 Özel Kural: Fatura No genelde A ile başlar ve 15 hanelidir.
        // Regex: \bA\d{15}\b
        // InvoiceParser bulamadıysa veya yanlış bulduysa burada düzeltebiliriz.
        if invoice.invoiceNo.isEmpty {
            if let range = rawText.range(of: #"\bA\d{15}\b"#, options: .regularExpression) {
                invoice.invoiceNo = String(rawText[range])
            }
        }
    }
}
