import Foundation
import FirebaseFirestore

/// Kullanıcı geri bildirimlerini (Düzeltmeleri) tutan model.
/// Sistem bu verileri kullanarak kendini geliştirecektir (Active Learning).
struct TrainingData: Codable, Identifiable {
    @DocumentID var id: String?
    
    var invoiceId: String
    var originalOCR: Invoice // OCR'ın ilk bulduğu hali
    var userCorrected: Invoice // Kullanıcının düzelttiği hali
    var diffs: [String] // Hangi alanların değiştiği (örn: ["totalAmount", "merchantName"])
    var createdAt: Date = Date()
    
    // Hangi alanların değiştiğini bulur
    static func detectDiffs(original: Invoice, final: Invoice) -> [String] {
        var diffs: [String] = []
        
        if original.merchantName != final.merchantName { diffs.append("merchantName") }
        if original.merchantTaxID != final.merchantTaxID { diffs.append("merchantTaxID") }
        if abs(original.totalAmount - final.totalAmount) > 0.01 { diffs.append("totalAmount") }
        if abs(original.taxAmount - final.taxAmount) > 0.01 { diffs.append("taxAmount") }
        if original.invoiceDate != final.invoiceDate { diffs.append("invoiceDate") }
        if original.invoiceNo != final.invoiceNo { diffs.append("invoiceNo") }
        if original.ettn != final.ettn { diffs.append("ettn") }
        
        return diffs
    }
}
