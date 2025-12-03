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
        
        // Trendyol pazaryeri faturalarında satıcı tespiti:
        // extractMerchantName zaten sol üst bloğun ilk satırını buluyor
        // Eğer bu satır "DSM Grup" içermiyorsa, bu gerçek satıcıdır (pazaryeri üzerinden satış yapan)
        // Eğer "DSM Grup" içeriyorsa, bu Trendyol'un kendi faturasıdır
        
        let currentName = invoice.merchantName.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Eğer satıcı adı DSM Grup içermiyorsa, bu gerçek satıcıdır - olduğu gibi bırak
        if !currentName.contains("DSM GRUP") && !currentName.contains("TRENDYOL") {
            // Gerçek satıcı bulundu, değişiklik yapma
            return
        }
        
        // Eğer DSM Grup ise, bu Trendyol'un kendi faturası
        // Pazaryeri olduğunu belirt (isteğe bağlı, kullanıcı deneyimi için)
        if currentName.contains("DSM GRUP") {
            // Trendyol'un kendi faturası - mevcut ismi koru
            // İsterseniz "(Pazaryeri)" ekleyebilirsiniz ama genelde gerek yok
            // Çünkü zaten Trendyol profili aktif olduğu için pazaryeri olduğu anlaşılıyor
        }
    }
}
