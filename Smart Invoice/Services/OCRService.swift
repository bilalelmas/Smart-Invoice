import Foundation
import Vision
import VisionKit
import UIKit
import Combine
import CoreImage

/// OCR İşlemlerinden sorumlu servis sınıfı.
/// Python projesindeki 'FaturaRegexAnaliz' sınıfının iOS karşılığıdır.
class OCRService: ObservableObject, OCRServiceProtocol {
    
    @Published var recognizedText: String = ""
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0.0 // 0.0 - 1.0
    
    // Dependency Injection
    private let invoiceParser: InvoiceParserProtocol
    
    init(invoiceParser: InvoiceParserProtocol = InvoiceParser.shared) {
        self.invoiceParser = invoiceParser
    }
    
    /// Görüntüden metin okuma işlemini başlatır (Apple Vision API)
    /// - Parameter image: Taranacak fatura görüntüsü
    /// - Returns: Parse edilmiş Invoice
    /// - Throws: OCRServiceError
    func recognizeText(from image: UIImage) async throws -> Invoice {
        await MainActor.run {
            self.isProcessing = true
            self.progress = 0.0
        }
        
        print("🖼️ OCR başlıyor, görüntü boyutu: \(image.size), scale: \(image.scale), orientation: \(image.imageOrientation.rawValue)")
        
        // Görüntü orientation'ını düzelt (galeri resimleri için önemli)
        let orientedImage = image.fixedOrientation()
        
        guard let originalCGImage = orientedImage.cgImage else {
            await MainActor.run {
                self.isProcessing = false
                self.progress = 0.0
            }
            throw OCRServiceError.invalidImage
        }
        
        // Galeri görselleri için daha agresif preprocessing gerekebilir
        // Orientation düzeltmesi yapıldı, şimdi preprocessing yapalım
        // Önce preprocessing yapılmış görüntü ile OCR dene (galeri görselleri için önemli)
        print("🔄 İlk deneme: Preprocessing yapılmış görüntü ile OCR")
        let preprocessedImage = await preprocessImage(orientedImage)
        guard let preprocessedCGImage = preprocessedImage.cgImage else {
            await MainActor.run {
                self.isProcessing = false
                self.progress = 0.0
            }
            throw OCRServiceError.invalidImage
        }
        
        do {
            let result = try await performOCR(on: preprocessedCGImage, size: preprocessedImage.size, isRetry: false)
            return result
        } catch {
            print("⚠️ Preprocessing yapılmış görüntü ile OCR başarısız, orijinal görüntü ile tekrar deneniyor...")
            
            // Preprocessing başarısız olduysa orijinal görüntü ile tekrar dene
            print("🔄 İkinci deneme: Orijinal görüntü ile OCR (preprocessing olmadan)")
            do {
                return try await performOCR(on: originalCGImage, size: orientedImage.size, isRetry: true)
            } catch {
                // Her iki deneme de başarısız, hatayı fırlat
                print("❌ Tüm OCR denemeleri başarısız")
                throw error
            }
        }
    }
    
    /// OCR işlemini gerçekleştirir
    private func performOCR(on cgImage: CGImage, size: CGSize, isRetry: Bool = false) async throws -> Invoice {
        // OCR başlıyor (20% progress)
        await MainActor.run {
            self.progress = 0.2
        }
        
        // Vision request'i async/await ile sarmala
        return try await withCheckedThrowingContinuation { continuation in
            // İstek oluştur
            let request = VNRecognizeTextRequest { [weak self] request, error in
                guard let self = self else {
                    continuation.resume(throwing: OCRServiceError.processingError("Service deallocated"))
                    return
                }
                
                // Hata kontrolü
                if let error = error {
                    Task { @MainActor in
                        self.isProcessing = false
                    }
                    continuation.resume(throwing: OCRServiceError.recognitionError(error.localizedDescription))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    print("❌ OCR: Observations bulunamadı")
                    Task { @MainActor in
                        self.isProcessing = false
                        self.progress = 0.0
                    }
                    continuation.resume(throwing: OCRServiceError.recognitionError("Metin bulunamadı"))
                    return
                }
                
                print("✅ OCR: \(observations.count) adet text observation bulundu")
                
                // OCR tamamlandı (60% progress)
                Task { @MainActor in
                    self.progress = 0.6
                }
                
                // Okunan metinleri bloklara dönüştür
                let blocks: [TextBlock] = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else {
                        print("⚠️ OCR: Candidate bulunamadı")
                        return nil
                    }
                    
                    // Vision koordinat sistemi (0,0 sol alt) -> UIKit (0,0 sol üst) dönüşümü
                    // Vision'ın boundingBox'ı sol alt köşeden başlar, UIKit sol üst köşeden başlar
                    let uikitFrame = TextBlock.convertVisionToUIKit(observation.boundingBox)
                    
                    return TextBlock(
                        text: candidate.string,
                        frame: uikitFrame, // UIKit koordinat sistemine dönüştürülmüş (0-1 arası)
                        confidence: candidate.confidence // OCR confidence değeri
                    )
                }
                
                print("✅ OCR: \(blocks.count) adet TextBlock oluşturuldu")
                
                // Debug için ham metni de oluştur
                let extractedText = blocks.map { $0.text }.joined(separator: "\n")
                print("📝 OCR: Ham metin uzunluğu: \(extractedText.count) karakter")
                
                if blocks.isEmpty && extractedText.isEmpty {
                    print("❌ OCR: Hem blocks hem de extractedText boş!")
                }
                
                Task { @MainActor in
                    self.recognizedText = extractedText
                    self.progress = 0.8 // Parsing başlıyor
                }
                
                // Konumsal Analiz ile Parse Et
                Task {
                    do {
                        print("🔄 Parser'a gönderiliyor: \(blocks.count) blocks, \(extractedText.count) karakter metin")
                        let draftInvoice = try await self.invoiceParser.parse(blocks: blocks, rawText: extractedText)
                        
                        print("✅ Parser başarılı: \(draftInvoice.merchantName.isEmpty ? "Satıcı bulunamadı" : "Satıcı: \(draftInvoice.merchantName)")")
                        
                        // Tamamlandı (100% progress)
                        await MainActor.run {
                            self.progress = 1.0
                            self.isProcessing = false
                        }
                        
                        continuation.resume(returning: draftInvoice)
                    } catch {
                        print("❌ Parser hatası: \(error.localizedDescription)")
                        if let parserError = error as? InvoiceParserError {
                            print("   Parser error type: \(parserError)")
                        }
                        await MainActor.run {
                            self.isProcessing = false
                            self.progress = 0.0
                        }
                        continuation.resume(throwing: OCRServiceError.processingError(error.localizedDescription))
                    }
                }
            }
            
            // Maksimum doğruluk için Vision Framework ayarları
            request.recognitionLanguages = ["tr-TR", "en-US"] // Türkçe ve İngilizce dil desteği
            request.recognitionLevel = .accurate // En yüksek doğruluk seviyesi (hız yerine doğruluk)
            request.usesLanguageCorrection = true // Dil düzeltmesi aktif
            request.minimumTextHeight = 0.0 // Minimum metin yüksekliği (0 = otomatik, tüm metinleri yakala)
            // Not: customWords özelliği Vision Framework'te mevcut değil, bu yüzden eklenmedi
            
            // Vision request options
            let options: [VNImageOption: Any] = [
                .ciContext: AppConstants.ciContext // Shared Core Image context
            ]
            
            // Görüntü orientation'ını otomatik algıla
            // Vision Framework orientation'ı otomatik algılayabilir, ama manuel belirtmek daha güvenilir
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: options)
            
            print("🔍 Vision request ayarları:")
            print("   - Diller: \(request.recognitionLanguages)")
            print("   - Seviye: \(request.recognitionLevel == .accurate ? "accurate" : "fast")")
            print("   - Dil düzeltmesi: \(request.usesLanguageCorrection)")
            print("   - Görüntü boyutu: \(cgImage.width)x\(cgImage.height)")
            let colorSpaceName: String = (cgImage.colorSpace?.name as String?) ?? "bilinmiyor"
            print("   - Görüntü color space: \(colorSpaceName)")
            print("   - Görüntü bits per component: \(cgImage.bitsPerComponent)")
            print("   - Görüntü bits per pixel: \(cgImage.bitsPerPixel)")
            
            // Arka planda çalıştır (UI donmasın diye)
            // Background queue kullanarak UI thread'ini bloklamadan OCR yap
            Task.detached(priority: .userInitiated) {
                do {
                    try requestHandler.perform([request])
                } catch {
                    await MainActor.run {
                        self.isProcessing = false
                        self.progress = 0.0
                    }
                    continuation.resume(throwing: OCRServiceError.recognitionError(error.localizedDescription))
                }
            }
        }
    }
    
    // MARK: - Image Preprocessing
    
    /// Görüntüyü OCR için optimize eder
    /// - Parameter image: Orijinal görüntü
    /// - Returns: İşlenmiş görüntü
    private func preprocessImage(_ image: UIImage) async -> UIImage {
        let size = image.size
        let maxSize = max(size.width, size.height)
        
        // 1. Minimum boyut kontrolü (OCR için en az 800px genişlik/yükseklik)
        let minDimension: CGFloat = 800
        let maxDimension: CGFloat = 3000
        
        // Çok küçük görüntüleri büyüt
        if maxSize < minDimension {
            let scale = minDimension / maxSize
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            print("📏 Görüntü küçük, büyütülüyor: \(size) -> \(newSize)")
            let resized = await resizeImage(image, to: newSize)
            // Küçük görüntüler için daha agresif iyileştirme
            return await enhanceImage(resized)
        }
        
        // Çok büyük görüntüleri küçült
        if maxSize > maxDimension {
            let scale = maxDimension / maxSize
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            print("📏 Görüntü büyük, küçültülüyor: \(size) -> \(newSize)")
            let resized = await resizeImage(image, to: newSize)
            return await enhanceImageLight(resized)
        }
        
        // Boyut uygunsa, kontrast ve parlaklık iyileştirmesi yap
        // Galeri resimleri için daha agresif iyileştirme gerekebilir
        print("📏 Görüntü boyutu uygun, iyileştirme yapılıyor")
        return await enhanceImage(image)
    }
    
    /// Görüntüyü belirli boyuta resize eder
    private func resizeImage(_ image: UIImage, to newSize: CGSize) async -> UIImage {
        return await withCheckedContinuation { continuation in
            UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
            defer { UIGraphicsEndImageContext() }
            
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            continuation.resume(returning: resizedImage)
        }
    }
    
    /// Görüntüyü gerekirse yeniden boyutlandırır
    private func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) async -> UIImage {
        let size = image.size
        let maxSize = max(size.width, size.height)
        
        // Eğer görüntü zaten küçükse, işlem yapma
        if maxSize <= maxDimension {
            return image
        }
        
        // Aspect ratio'yu koruyarak resize et
        let scale = maxDimension / maxSize
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        return await withCheckedContinuation { continuation in
            UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
            defer { UIGraphicsEndImageContext() }
            
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            continuation.resume(returning: resizedImage)
        }
    }
    
    /// Görüntüyü hafif iyileştirir (PDF görüntüleri için)
    private func enhanceImageLight(_ image: UIImage) async -> UIImage {
        guard let ciImage = CIImage(image: image) else {
            return image
        }
        
        // Core Image filters
        // Core Image filters
        let context = AppConstants.ciContext
        
        // Hafif kontrast artırma (PDF görüntüleri için daha az agresif)
        guard let contrastFilter = CIFilter(name: "CIColorControls") else {
            return image
        }
        contrastFilter.setValue(ciImage, forKey: kCIInputImageKey)
        contrastFilter.setValue(1.1, forKey: kCIInputContrastKey) // %10 kontrast artışı (daha hafif)
        contrastFilter.setValue(1.05, forKey: kCIInputBrightnessKey) // %5 parlaklık artışı
        
        guard let enhancedCI = contrastFilter.outputImage else {
            return image
        }
        
        return renderCIImage(enhancedCI, context: context, size: image.size) ?? image
    }
    
    /// Görüntüyü iyileştirir (kontrast, parlaklık) - Galeri resimleri için agresif iyileştirme
    private func enhanceImage(_ image: UIImage) async -> UIImage {
        guard let ciImage = CIImage(image: image) else {
            print("⚠️ CIImage oluşturulamadı, orijinal görüntü döndürülüyor")
            return image
        }
        
        // Core Image filters
        // Core Image filters
        let context = AppConstants.ciContext
        var currentImage = ciImage
        
        // 1. Gürültü azaltma (galeri görselleri için önemli)
        if let noiseReductionFilter = CIFilter(name: "CINoiseReduction") {
            // Set input image
            noiseReductionFilter.setValue(currentImage, forKey: kCIInputImageKey)
            // CINoiseReduction uses keys: inputNoiseLevel and inputSharpness
            // Use typed properties when available, otherwise fall back to string keys
            if noiseReductionFilter.responds(to: Selector(("setInputNoiseLevel:"))) {
                // No direct setter available via Swift, keep KVC with proper key names
                noiseReductionFilter.setValue(0.02, forKey: "inputNoiseLevel")
            } else {
                noiseReductionFilter.setValue(0.02, forKey: "inputNoiseLevel")
            }
            if noiseReductionFilter.responds(to: Selector(("setInputSharpness:"))) {
                noiseReductionFilter.setValue(0.4, forKey: "inputSharpness")
            } else {
                noiseReductionFilter.setValue(0.4, forKey: "inputSharpness")
            }
            if let output = noiseReductionFilter.outputImage {
                currentImage = output
                print("✅ Gürültü azaltma uygulandı")
            }
        }
        
        // 2. Kontrast ve parlaklık artırma (galeri resimleri için daha agresif)
        guard let contrastFilter = CIFilter(name: "CIColorControls") else {
            print("⚠️ CIColorControls filter bulunamadı")
            return image
        }
        contrastFilter.setValue(currentImage, forKey: kCIInputImageKey)
        contrastFilter.setValue(1.4, forKey: kCIInputContrastKey) // %40 kontrast artışı (daha agresif)
        contrastFilter.setValue(1.15, forKey: kCIInputBrightnessKey) // %15 parlaklık artışı
        contrastFilter.setValue(1.1, forKey: kCIInputSaturationKey) // %10 doygunluk artışı
        
        guard let enhancedCI = contrastFilter.outputImage else {
            print("⚠️ Enhanced CIImage oluşturulamadı")
            return image
        }
        currentImage = enhancedCI
        
        // 3. Sharpening ekle (metin okunabilirliğini artırır - daha agresif)
        if let sharpenFilter = CIFilter(name: "CISharpenLuminance") {
            sharpenFilter.setValue(currentImage, forKey: kCIInputImageKey)
            // CISharpenLuminance uses keys: inputSharpness and inputRadius
            sharpenFilter.setValue(0.6, forKey: kCIInputSharpnessKey)
            sharpenFilter.setValue(0.4, forKey: kCIInputRadiusKey)
            if let sharpenedCI = sharpenFilter.outputImage {
                currentImage = sharpenedCI
                print("✅ Sharpening uygulandı")
            }
        }
        
        // 4. Exposure düzeltmesi (galeri görselleri için)
        if let exposureFilter = CIFilter(name: "CIExposureAdjust") {
            exposureFilter.setValue(currentImage, forKey: kCIInputImageKey)
            exposureFilter.setValue(0.2, forKey: kCIInputEVKey) // Hafif exposure artışı
            
            if let exposedCI = exposureFilter.outputImage {
                currentImage = exposedCI
                print("✅ Exposure düzeltmesi uygulandı")
            }
        }
        
        return renderCIImage(currentImage, context: context, size: image.size) ?? image
    }
    
    /// CIImage'i UIImage'e dönüştürür
    private func renderCIImage(_ ciImage: CIImage, context: CIContext, size: CGSize) -> UIImage? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
}

// MARK: - UIImage Extension for Orientation Fix

extension UIImage {
    /// Görüntü orientation'ını düzeltir (galeri resimleri için)
    func fixedOrientation() -> UIImage {
        // Eğer orientation .up ise, dönüşüm gerekmez
        if imageOrientation == .up {
            return self
        }
        
        // Orientation'ı düzelt
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}
