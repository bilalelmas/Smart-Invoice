import Foundation

/// Bilinmeyen satıcılar için varsayılan profil.
struct DefaultProfile: VendorProfile {
    var vendorName: String { "Bilinmeyen Satıcı" }
    
    func applies(to textLowercased: String) -> Bool {
        return true // Her zaman eşleşir (Fallback)
    }
    
    func applyRules(to invoice: inout Invoice, rawText: String) {
        // Varsayılan profilde özel bir kural yok, InvoiceParser sonuçlarına güveniyoruz.
        // Ancak gerekirse burada genel temizlik yapılabilir.
    }
}
