import Foundation

/// Satıcıya özel fatura işleme kurallarını tanımlayan protokol.
/// Tez Notu: Burada 'Strategy Design Pattern' kullanılarak farklı satıcı formatları
/// tek bir arayüz üzerinden yönetilmiştir. (Bkz: profile_base.py)
protocol VendorProfile {
    /// Profilin adı (Örn: Trendyol, A101)
    var vendorName: String { get }
    
    /// Bu profilin verilen metne uygulanıp uygulanamayacağını kontrol eder.
    /// - Parameter text: OCR'dan gelen ham metin (küçük harfe çevrilmiş)
    func applies(to textLowercased: String) -> Bool
    
    /// Satıcıya özel düzeltme kurallarını faturaya uygular.
    /// - Parameters:
    ///   - invoice: Düzenlenecek fatura objesi (inout ile referans olarak gelir)
    ///   - rawText: Orijinal ham metin
    func applyRules(to invoice: inout Invoice, rawText: String)
}
