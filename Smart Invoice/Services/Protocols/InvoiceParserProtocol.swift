import Foundation

/// Invoice parsing işlemleri için protocol
/// Dependency Injection ve test edilebilirlik için
protocol InvoiceParserProtocol {
    /// Konumsal Analiz Motoru (Spatial Analysis Engine)
    /// Blokları koordinatlarına göre satırlara ayırır ve işler.
    /// - Parameters:
    ///   - blocks: OCR'dan gelen text blokları
    ///   - rawText: Ham metin (bloklar yoksa kullanılır)
    /// - Returns: Parse edilmiş Invoice
    /// - Throws: InvoiceParserError
    func parse(blocks: [TextBlock], rawText: String?) async throws -> Invoice
    
    /// String bazlı parse (geriye dönük uyumluluk)
    /// - Parameter text: Ham metin
    /// - Returns: Parse edilmiş Invoice
    func parse(text: String) async -> Invoice
}

