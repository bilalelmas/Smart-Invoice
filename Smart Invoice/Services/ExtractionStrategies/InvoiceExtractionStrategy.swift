import Foundation

/// Stratejilerin ihtiyaç duyduğu ham verileri tutan context yapısı
struct ExtractionContext {
    let blocks: [TextBlock]
    let lines: [TextLine]
    let rawText: String
    let profile: VendorProfile? // Opsiyonel profil bilgisi
    
    // Yardımcı veri erişimcileri
    var fullText: String { rawText }
    var cleanLines: [String] {
        rawText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// Fatura verisi çıkarma stratejisi protokolü
protocol InvoiceExtractionStrategy {
    /// Context'ten veri çıkarır ve invoice nesnesini günceller
    /// - Parameters:
    ///   - context: Ham veri
    ///   - invoice: Güncellenecek fatura nesnesi (inout)
    func extract(context: ExtractionContext, invoice: inout Invoice)
}
