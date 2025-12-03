import Foundation
import Vision
import VisionKit
import UIKit
import Combine

/// OCR İşlemlerinden sorumlu servis sınıfı.
/// Python projesindeki 'FaturaRegexAnaliz' sınıfının iOS karşılığıdır.
class OCRService: ObservableObject {
    
    @Published var recognizedText: String = ""
    @Published var isProcessing: Bool = false
    
    /// Görüntüden metin okuma işlemini başlatır (Apple Vision API)
    /// - Parameter image: Taranacak fatura görüntüsü
    /// - Completion: İşlem bitince Result<Invoice, Error> döner
    func recognizeText(from image: UIImage, completion: @escaping (Result<Invoice, Error>) -> Void) {
        self.isProcessing = true
        
        guard let cgImage = image.cgImage else {
            DispatchQueue.main.async {
                self.isProcessing = false
                completion(.failure(OCRServiceError.invalidImage))
            }
            return
        }
        
        // İstek oluştur
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            
            // Hata kontrolü
            if let error = error {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(.failure(OCRServiceError.recognitionError(error.localizedDescription)))
                }
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(.failure(OCRServiceError.recognitionError("Metin bulunamadı")))
                }
                return
            }
            
            // Okunan metinleri bloklara dönüştür
            let blocks: [TextBlock] = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                
                // Vision koordinat sistemi (0,0 sol alt) -> UIKit (0,0 sol üst) dönüşümü
                // Vision'ın boundingBox'ı sol alt köşeden başlar, UIKit sol üst köşeden başlar
                let uikitFrame = TextBlock.convertVisionToUIKit(observation.boundingBox)
                
                return TextBlock(
                    text: candidate.string,
                    frame: uikitFrame, // UIKit koordinat sistemine dönüştürülmüş (0-1 arası)
                    confidence: candidate.confidence // OCR confidence değeri
                )
            }
            
            // Debug için ham metni de oluştur
            let extractedText = blocks.map { $0.text }.joined(separator: "\n")
            
            DispatchQueue.main.async {
                self.recognizedText = extractedText
                self.isProcessing = false
                
                // Konumsal Analiz ile Parse Et
                do {
                    let draftInvoice = try InvoiceParser.shared.parse(blocks: blocks, rawText: extractedText)
                    completion(.success(draftInvoice))
                } catch {
                    completion(.failure(OCRServiceError.processingError(error.localizedDescription)))
                }
            }
        }
        
        // Türkçe ve İngilizce dil desteği (Python projesindeki 'tur' ve 'eng' ayarı gibi)
        request.recognitionLanguages = ["tr-TR", "en-US"]
        request.recognitionLevel = .accurate // Hız yerine doğruluk odaklı (Tez için önemli)
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        // Arka planda çalıştır (UI donmasın diye)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(.failure(OCRServiceError.recognitionError(error.localizedDescription)))
                }
            }
        }
    }
}
