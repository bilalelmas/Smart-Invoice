import Foundation

/// Trendyol faturaları için ayrıştırma profili.
struct TrendyolProfile: VendorProfile {
    var vendorName: String { "Trendyol" }
    
    func applies(to textLowercased: String) -> Bool {
        return textLowercased.contains("trendyol") || textLowercased.contains("dsm grup")
    }
    
    func applyRules(to invoice: inout Invoice, rawText: String) {
        // Trendyol faturalarında satıcı adı sabittir
        invoice.merchantName = vendorName
        
        // Trendyol'a özel tarih formatı veya diğer kurallar buraya eklenebilir
        // Örn: Eğer tarih bulunamadıysa ve metinde "Sipariş Tarihi: ..." varsa oradan al
        
        // Şimdilik sadece ismini garantiye alıyoruz, diğer işleri InvoiceParser yapıyor.
    }
}
