import Foundation
import Vision
import UIKit

/// Fatura işleme motoru.
/// The core engine for processing invoices.
class InvoiceParser {
    
    // Mevcut profiller
    private let profiles: [VendorProfileProtocol] = [
        TrendyolProfile(),
        A101Profile(),
        DefaultProfile()
    ]
    
    /// Görüntüyü işler ve Fatura nesnesi döndürür.
    /// Processes the image and returns an Invoice object.
    /// - Parameter image: Taranacak fatura görüntüsü.
    /// - Parameter completion: Sonuç bloğu (Fatura veya Hata).
    func parse(image: UIImage, completion: @escaping (Result<Invoice, Error>) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(.failure(NSError(domain: "InvoiceParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Geçersiz görüntü"])))
            return
        }
        
        // Vision İsteği
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(.failure(NSError(domain: "InvoiceParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "Metin bulunamadı"])))
                return
            }
            
            // 1. Vision OCR -> TextBlock Dönüşümü
            let textBlocks = self.createTextBlocks(from: observations, in: image)
            
            // 2. Spatial Grouping (Opsiyonel: Satır bazlı analiz için kullanılabilir)
            // let textLines = self.groupBlocksIntoLines(blocks: textBlocks)
            
            // 3. Vendor Detection & Parsing
            let invoice = self.detectAndParse(textBlocks: textBlocks)
            
            completion(.success(invoice))
        }
        
        // Türkçe dil desteği ve doğruluk ayarı
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["tr-TR", "en-US"]
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Vision gözlemlerini TextBlock yapısına dönüştürür.
    private func createTextBlocks(from observations: [VNRecognizedTextObservation], in image: UIImage) -> [TextBlock] {
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            
            // Vision koordinatları (0,0 sol alt) -> UIKit koordinatları (0,0 sol üst) dönüşümü gerekebilir
            // Ancak şimdilik normalize edilmiş koordinatları (0-1 arası) tutuyoruz.
            // Gerekirse image.size ile çarpılarak pixel koordinatına dönüştürülebilir.
            
            return TextBlock(text: candidate.string, boundingBox: observation.boundingBox)
        }
    }
    
    /// Metin bloklarını Y koordinatına göre satırlara gruplar.
    /// Groups text blocks into lines based on Y coordinate.
    private func groupBlocksIntoLines(blocks: [TextBlock]) -> [TextLine] {
        // Y koordinatına göre sırala (Vision'da Y yukarıdan aşağıya 1->0 olabilir veya tam tersi, kontrol edilmeli)
        // Vision'da (0,0) sol alt köşedir. Y değeri yukarı çıktıkça artar.
        // Ancak biz genellikle yukarıdan aşağı okuruz.
        
        let sortedBlocks = blocks.sorted { $0.boundingBox.maxY > $1.boundingBox.maxY } // Yukarıdan aşağıya
        
        var lines: [TextLine] = []
        
        for block in sortedBlocks {
            // Mevcut satırlardan birine uyuyor mu? (Y ekseninde yakınlık)
            // Eşik değeri (threshold) belirlenmeli. Örn: 0.02 (Görüntü yüksekliğinin %2'si)
            let threshold: CGFloat = 0.02
            
            if let index = lines.firstIndex(where: { abs($0.averageY - block.midY) < threshold }) {
                lines[index].blocks.append(block)
            } else {
                lines.append(TextLine(blocks: [block]))
            }
        }
        
        return lines
    }
    
    /// Satıcıyı tespit eder ve uygun profili kullanarak ayrıştırma yapar.
    private func detectAndParse(textBlocks: [TextBlock]) -> Invoice {
        // Tüm metni birleştirip satıcı adı arayalım
        let fullText = textBlocks.map { $0.text }.joined(separator: " ")
        
        // Profilleri gez
        for profile in profiles {
            if profile.isMatch(text: fullText) {
                print("Tespit edilen satıcı: \(profile.vendorName)")
                if let invoice = profile.parse(textBlocks: textBlocks) {
                    return invoice
                }
            }
        }
        
        // Hiçbiri uymazsa varsayılan profil
        print("Satıcı tanınamadı, varsayılan profil kullanılıyor.")
        return profiles.last!.parse(textBlocks: textBlocks)!
    }
}
