import Foundation
import UIKit

/// OCR işlemleri için protocol
/// Dependency Injection ve test edilebilirlik için
protocol OCRServiceProtocol {
    var recognizedText: String { get }
    var isProcessing: Bool { get }
    
    /// Görüntüden metin okuma işlemini başlatır
    /// - Parameter image: Taranacak fatura görüntüsü
    /// - Returns: Parse edilmiş Invoice
    /// - Throws: OCRServiceError
    func recognizeText(from image: UIImage) async throws -> Invoice
}

