import Foundation
import CoreGraphics

/// OCR'dan gelen ham metin bloğu ve koordinat bilgisi.
/// Python projesindeki blok yapısının iOS karşılığıdır.
struct TextBlock: Identifiable {
    let id = UUID()
    let text: String
    let frame: CGRect // Normalleştirilmiş koordinatlar (0-1 arası)
    
    // Yardımcı özellikler
    var x: CGFloat { frame.origin.x }
    var y: CGFloat { frame.origin.y }
    var width: CGFloat { frame.width }
    var height: CGFloat { frame.height }
    
    var midY: CGFloat { frame.midY }
}

/// Aynı satırda bulunan TextBlock'ların birleşimi.
struct TextLine: Identifiable {
    let id = UUID()
    let blocks: [TextBlock]
    let text: String
    let frame: CGRect
    
    init(blocks: [TextBlock]) {
        self.blocks = blocks.sorted { $0.x < $1.x } // Soldan sağa sırala
        self.text = self.blocks.map { $0.text }.joined(separator: " ")
        
        // Kapsayıcı dikdörtgeni hesapla
        let minX = blocks.map { $0.x }.min() ?? 0
        let minY = blocks.map { $0.y }.min() ?? 0
        let maxX = blocks.map { $0.x + $0.width }.max() ?? 0
        let maxY = blocks.map { $0.y + $0.height }.max() ?? 0
        
        self.frame = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
