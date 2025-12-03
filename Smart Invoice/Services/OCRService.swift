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
            
            // Okunan metinleri bloklara dönüştür
            let blocks: [TextBlock] = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                
                // Vision koordinat sistemi (0,0 sol alt) -> UIKit (0,0 sol üst) dönüşümü gerekebilir.
                // Ancak TextBlock içinde sadece bağıl konum tutuyoruz, sıralama için Y'yi olduğu gibi kullanabiliriz.
                // Vision'da Y yukarı doğru artar. Bizim Row Clustering "Y > Y" diyerek sıralıyor, yani yukarıdan aşağıya (büyükten küçüğe)
                // Bu yüzden boundingBox'ı direkt kullanabiliriz.
                
                return TextBlock(
                    text: candidate.string,
                    frame: observation.boundingBox // Normalleştirilmiş (0-1 arası)
                )
            }
            
            // Debug için ham metni de oluştur
            let extractedText = blocks.map { $0.text }.joined(separator: "\n")
            
            DispatchQueue.main.async {
                self.recognizedText = extractedText
                self.isProcessing = false
                
                // Konumsal Analiz ile Parse Et
                let draftInvoice = InvoiceParser.shared.parse(blocks: blocks, rawText: extractedText)
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
