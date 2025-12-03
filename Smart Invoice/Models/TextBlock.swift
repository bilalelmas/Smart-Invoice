import Foundation
import CoreGraphics

/// OCR'dan gelen ham metin bloğu ve koordinat bilgisi.
/// Python projesindeki blok yapısının iOS karşılığıdır.
struct TextBlock: Identifiable {
    let id = UUID()
    let text: String
    let frame: CGRect // Normalleştirilmiş koordinatlar (0-1 arası)
    let confidence: Float // OCR confidence değeri (0.0 - 1.0)
    
    // Yardımcı özellikler
    var x: CGFloat { frame.origin.x }
    var y: CGFloat { frame.origin.y }
    var width: CGFloat { frame.width }
    var height: CGFloat { frame.height }
    
    var midY: CGFloat { frame.midY }
    
    /// Vision Framework koordinat sisteminden (sol alt köşe) UIKit koordinat sistemine (sol üst köşe) dönüştürür.
    /// Vision: (0,0) sol alt, (1,1) sağ üst
    /// UIKit: (0,0) sol üst, (1,1) sağ alt
    /// - Parameter visionRect: Vision Framework'ün normalleştirilmiş boundingBox'ı
    /// - Returns: UIKit koordinat sistemine dönüştürülmüş CGRect
    static func convertVisionToUIKit(_ visionRect: CGRect) -> CGRect {
        // Vision'da Y koordinatı sol alttan başlar, UIKit'de sol üstten başlar
        // Dönüşüm: y_uiKit = 1 - (y_vision + height_vision)
        let x = visionRect.origin.x
        let y = 1 - (visionRect.origin.y + visionRect.height)
        let width = visionRect.width
        let height = visionRect.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
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
