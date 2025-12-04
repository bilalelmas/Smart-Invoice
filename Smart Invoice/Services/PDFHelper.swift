import UIKit
import PDFKit

struct PDFHelper {
    /// PDF dosyasının ilk sayfasını UIImage'e çevirir
    static func pdfToImage(url: URL) -> UIImage? {
        // Security scoped resource erişimi
        let canAccess = url.startAccessingSecurityScopedResource()
        defer {
            if canAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ PDF dosyası bulunamadı: \(url.path)")
            return nil
        }
        
        guard let document = PDFDocument(url: url) else {
            print("❌ PDFDocument oluşturulamadı: \(url.lastPathComponent)")
            return nil
        }
        
        guard document.pageCount > 0 else {
            print("❌ PDF'de sayfa yok: \(url.lastPathComponent)")
            return nil
        }
        
        guard let page = document.page(at: 0) else {
            print("❌ PDF'in ilk sayfası alınamadı: \(url.lastPathComponent)")
            return nil
        }
        
        let pageRect = page.bounds(for: .mediaBox)
        
        // Minimum boyut kontrolü
        guard pageRect.size.width > 0 && pageRect.size.height > 0 else {
            print("❌ PDF sayfa boyutu geçersiz: \(pageRect.size)")
            return nil
        }
        
        // OCR için optimal çözünürlük: 2000-3000px genişlik/yükseklik
        // PDF'ler genellikle 72 DPI'da, OCR için en az 200 DPI gerekli
        let targetDPI: CGFloat = 300.0
        let sourceDPI: CGFloat = 72.0
        let scale = targetDPI / sourceDPI
        
        // Maksimum boyut kontrolü (çok büyük PDF'ler için resize)
        let maxDimension: CGFloat = 3000
        let finalScale: CGFloat
        let scaledWidth = pageRect.size.width * scale
        let scaledHeight = pageRect.size.height * scale
        
        if max(scaledWidth, scaledHeight) > maxDimension {
            finalScale = maxDimension / max(scaledWidth, scaledHeight) * scale
        } else {
            finalScale = scale
        }
        
        let renderSize = CGSize(
            width: pageRect.size.width * finalScale,
            height: pageRect.size.height * finalScale
        )
        
        print("📐 PDF render boyutu: \(renderSize) (orijinal: \(pageRect.size), scale: \(finalScale))")
        
        // PDFKit'in page.thumbnail metodunu kullan (daha yüksek kalite)
        // Ama önce manuel render deneyelim, daha fazla kontrol için
        let renderScale: CGFloat = 2.0 // Retina için 2x
        let scaledSize = CGSize(
            width: renderSize.width * renderScale,
            height: renderSize.height * renderScale
        )
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = renderScale
        format.opaque = true
        format.preferredRange = .standard
        
        let renderer = UIGraphicsImageRenderer(size: scaledSize, format: format)
        
        let img = renderer.image { ctx in
            // Beyaz arka plan
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: scaledSize))
            
            // PDF koordinat sistemini UIKit'e çevir
            ctx.cgContext.translateBy(x: 0.0, y: scaledSize.height)
            ctx.cgContext.scaleBy(x: finalScale * renderScale, y: -finalScale * renderScale)
            
            // Yüksek kaliteli rendering ayarları
            ctx.cgContext.interpolationQuality = .high
            ctx.cgContext.setShouldAntialias(true)
            ctx.cgContext.setAllowsAntialiasing(true)
            ctx.cgContext.setRenderingIntent(.defaultIntent)
            ctx.cgContext.setFillColorSpace(CGColorSpaceCreateDeviceRGB())
            ctx.cgContext.setStrokeColorSpace(CGColorSpaceCreateDeviceRGB())
            
            // PDF sayfasını yüksek kalitede çiz
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        
        print("✅ PDF render tamamlandı - Final boyut: \(img.size), scale: \(img.scale), pixels: \(img.size.width * img.scale)x\(img.size.height * img.scale)")
        
        print("✅ PDF görüntüye dönüştürüldü: \(url.lastPathComponent), boyut: \(img.size), scale: \(img.scale)")
        return img
    }
}

