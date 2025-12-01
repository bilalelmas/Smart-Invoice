import Foundation
import CoreGraphics

/// A101 faturaları için ayrıştırma profili.
/// Parsing profile for A101 invoices.
struct A101Profile: VendorProfileProtocol {
    var vendorName: String { "A101" }
    
    func isMatch(text: String) -> Bool {
        return text.localizedCaseInsensitiveContains("A101") || 
               text.localizedCaseInsensitiveContains("Yeni Mağazacılık")
    }
    
    func parse(textBlocks: [TextBlock]) -> Invoice? {
        var invoice = Invoice()
        invoice.merchantName = vendorName
        
        let fullText = textBlocks.map { $0.text }.joined(separator: "\n")
        // invoice.rawText = fullText // Removed
        
        // A101 Özel Kural: Fatura No genelde A ile başlar ve 15 hanelidir.
        // Regex: \bA\d{15}\b
        if let invoiceNoRange = fullText.range(of: #"\bA\d{15}\b"#, options: .regularExpression) {
            invoice.invoiceNo = String(fullText[invoiceNoRange])
        }
        
        // Tarih
        if let dateRange = fullText.range(of: #"\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression) {
            let dateString = String(fullText[dateRange])
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM.yyyy"
            if let date = formatter.date(from: dateString) {
                invoice.invoiceDate = date
            }
        }
        
        return invoice
    }
}
