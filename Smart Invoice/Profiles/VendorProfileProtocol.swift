import Foundation

/// Satıcı profilleri için protokol.
/// Protocol for vendor profiles to implement parsing logic.
protocol VendorProfileProtocol {
    /// Satıcının adı (Örn: "Trendyol", "A101").
    var vendorName: String { get }
    
    /// Verilen metnin bu satıcıya ait olup olmadığını kontrol eder.
    /// Checks if the given text belongs to this vendor.
    /// - Parameter text: OCR'dan gelen ham metin.
    /// - Returns: Eşleşme varsa true.
    func isMatch(text: String) -> Bool
    
    /// Metin bloklarını analiz ederek Fatura nesnesi oluşturur.
    /// Parses text blocks to create an Invoice object.
    /// - Parameter textBlocks: OCR'dan gelen metin blokları.
    /// - Returns: Oluşturulan Fatura nesnesi veya nil.
    func parse(textBlocks: [TextBlock]) -> Invoice?
}
