import Foundation
import CoreGraphics

// MARK: - Invoice Models

/// Fatura ana verilerini temsil eden yapı.
/// Represents the main invoice data.
struct Invoice: Identifiable, Codable {
    var id: UUID = UUID()
    var merchantName: String?
    var date: Date?
    var totalAmount: Double?
    var taxAmount: Double?
    var invoiceNumber: String? // ETTN veya Fatura No
    var vkn: String? // Vergi Kimlik No
    var items: [InvoiceItem] = []
    
    // Ham metin verisi (Debug için)
    var rawText: String?
}

/// Fatura kalemlerini temsil eden yapı.
/// Represents individual line items in the invoice.
struct InvoiceItem: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var quantity: Double
    var unitPrice: Double
    var totalPrice: Double
}

// MARK: - Spatial Analysis Models

/// OCR'dan gelen ham metin bloğu ve koordinatları.
/// Represents a raw text block and its coordinates from OCR.
struct TextBlock: Identifiable {
    let id = UUID()
    let text: String
    let boundingBox: CGRect
    
    /// Bloğun merkez Y koordinatı (Satır gruplaması için).
    var midY: CGFloat {
        return boundingBox.midY
    }
}

/// Y koordinatına göre gruplanmış metin satırı.
/// Represents a line of text grouped by Y coordinate.
struct TextLine: Identifiable {
    let id = UUID()
    var blocks: [TextBlock]
    
    /// Satırdaki tüm metinlerin birleşimi.
    var text: String {
        return blocks.sorted(by: { $0.boundingBox.minX < $1.boundingBox.minX })
                     .map { $0.text }
                     .joined(separator: " ")
    }
    
    /// Satırın ortalama Y koordinatı.
    var averageY: CGFloat {
        guard !blocks.isEmpty else { return 0 }
        let sum = blocks.reduce(0) { $0 + $1.midY }
        return sum / CGFloat(blocks.count)
    }
}
