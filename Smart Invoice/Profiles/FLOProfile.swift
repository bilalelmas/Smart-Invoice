import Foundation

struct FLOProfile: VendorProfile {
    var vendorName: String = "FLO"
    
    func applies(to textLowercased: String) -> Bool {
        return textLowercased.contains("flo") ||
               textLowercased.contains("kinetix") ||
               textLowercased.contains("polaris")
    }
    
    func applyRules(to invoice: inout Invoice, rawText: String, blocks: [TextBlock]) {
        // FLO faturalarında satıcı adı bazen çok uzun çıkıyor, kısaltalım.
        invoice.merchantName = "FLO Mağazacılık A.Ş."
        
        // FLO'ya özel başka temizlik kuralları buraya eklenebilir.
        // Örn: Gereksiz "TCKN" etiketlerini temizleme (Python kodundaki gibi)
    }
}
