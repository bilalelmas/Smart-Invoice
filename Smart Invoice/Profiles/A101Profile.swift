import Foundation

/// A101 faturalarına özel iş mantığı.
/// Referans: Python projesi 'profile_a101.py'
struct A101Profile: VendorProfile {
    var vendorName: String = "A101"
    
    func applies(to textLowercased: String) -> Bool {
        return textLowercased.contains("a101") ||
               textLowercased.contains("yeni mağazacılık") ||
               textLowercased.contains("a101.com.tr")
    }
    
    func applyRules(to invoice: inout Invoice, rawText: String) {
        // Kural 1: Fatura No Fallback
        // A101 faturaları bazen standart dışı olup 'A' ile başlayıp 15 hane sürebiliyor.
        // Python Regex: \bA\d{15}\b
        if invoice.invoiceNo.isEmpty {
            if let customInvoiceNo = InvoiceParser.shared.extractString(from: rawText, pattern: "\\bA\\d{15}\\b") {
                invoice.invoiceNo = customInvoiceNo
            }
        }
        
        // Kural 2: Toplam Tutar Varyantları
        // "Ödenecek Tutar" bazen okunamazsa alternatif kelimelere bak.
        // Python Regex: (?:Ödenecek\s*Tutar|Genel\s*Toplam|Vergiler\s*Dahil\s*Toplam)...
        if invoice.totalAmount == 0.0 {
            let pattern = "(?:Ödenecek\\s*Tutar|Genel\\s*Toplam|Vergiler\\s*Dahil\\s*Toplam)\\s*[:\\-]?\\s*(\\d{1,3}(?:\\.\\d{3})*,\\d{2})"
            if let amountStr = InvoiceParser.shared.extractString(from: rawText, pattern: pattern) {
                invoice.totalAmount = InvoiceParser.shared.normalizeAmount(amountStr)
            }
        }
        
        // Satıcı ismini netleştir
        invoice.merchantName = "A101 Yeni Mağazacılık A.Ş."
    }
}
