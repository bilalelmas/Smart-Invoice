import Foundation
import Vision
import VisionKit
import UIKit

/// OCR İşlemlerinden sorumlu servis sınıfı.
/// Python projesindeki 'FaturaRegexAnaliz' sınıfının iOS karşılığıdır.
class OCRService: ObservableObject {
    
    @Published var recognizedText: String = ""
    @Published var isProcessing: Bool = false
    
    /// Görüntüden metin okuma işlemini başlatır (Apple Vision API)
    /// - Parameter image: Taranacak fatura görüntüsü
    /// - Completion: İşlem bitince 'Invoice' taslağı döner
    func recognizeText(from image: UIImage, completion: @escaping (Invoice?) -> Void) {
        self.isProcessing = true
        
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        
        // İstek oluştur
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            
            guard let observations = request.results as? [VNRecognizedTextObservation],
                  error == nil else {
                print("OCR Hatası: \(error?.localizedDescription ?? "Bilinmiyor")")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(nil)
                }
                return
            }
            
            // Okunan metinleri birleştir (Debug ve basit regex için)
            let extractedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            
            DispatchQueue.main.async {
                self.recognizedText = extractedText
                self.isProcessing = false
                
                // Ham metni anlamlandır ve Invoice objesine çevir
                // Artık tüm mantık InvoiceParser içinde (Hybrid: Regex + Strategy)
                let draftInvoice = InvoiceParser.shared.parse(text: extractedText)
                completion(draftInvoice)
            }
        }
        
        // Türkçe ve İngilizce dil desteği (Python projesindeki 'tur' ve 'eng' ayarı gibi)
        request.recognitionLanguages = ["tr-TR", "en-US"]
        request.recognitionLevel = .accurate // Hız yerine doğruluk odaklı (Tez için önemli)
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        // Arka planda çalıştır (UI donmasın diye)
        DispatchQueue.global(qos: .userInitiated).async {
            try? requestHandler.perform([request])
        }
    }
}
