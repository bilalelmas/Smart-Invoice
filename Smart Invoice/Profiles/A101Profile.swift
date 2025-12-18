import Foundation
import CoreGraphics

/// A101 faturalarına özel iş mantığı.
/// Referans: Python projesi 'profile_a101.py'
struct A101Profile: VendorProfile {
    var vendorName: String = "A101"
    
    var vendorKeywords: [String] { ["A101", "YENİ MAĞAZACILIK", "A-1O1"] }
    
    // A101 fişlerinde toplam genelde en alttadır
    var amountCoordinates: CGRect? {
        CGRect(x: 0.0, y: 0.6, width: 1.0, height: 0.4) // Alt %40'lık kısım
    }
    
    func applies(to textLowercased: String) -> Bool {
        return textLowercased.contains("a101") ||
               textLowercased.contains("yeni mağazacılık") ||
               textLowercased.contains("a101.com.tr")
    }
    
    func applyRules(to invoice: inout Invoice, rawText: String, blocks: [TextBlock]) {
        // Kural 1: Fatura No Fallback
        // A101 faturaları bazen standart dışı olup 'A' ile başlayıp 15 hane sürebiliyor.
        // Python Regex: \bA\d{15}\b
        if invoice.invoiceNo.isEmpty {
            if let customInvoiceNo = InvoiceParserHelper.extractInvoiceNo(from: rawText) {
                invoice.invoiceNo = customInvoiceNo
            }
        }
        
        // Kural 2: Toplam Tutar Varyantları
        // "Ödenecek Tutar" bazen okunamazsa alternatif kelimelere bak.
        // Python Regex: (?:Ödenecek\s*Tutar|Genel\s*Toplam|Vergiler\s*Dahil\s*Toplam)...
        if invoice.totalAmount == 0.0 {
            if let amount = InvoiceParserHelper.extractAmount(from: rawText) {
                invoice.totalAmount = amount
            }
        }
        
        // Satıcı ismini netleştir
        invoice.merchantName = "A101 Yeni Mağazacılık A.Ş."
    }
}
