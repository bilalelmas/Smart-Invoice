import Foundation
import Vision
import VisionKit
import UIKit

/// OCR İşlemlerinden sorumlu servis sınıfı.
/// Python projesindeki 'FaturaRegexAnaliz' sınıfının iOS karşılığıdır.
class OCRService: ObservableObject {
    
    @Published var recognizedText: String = ""
    @Published var isProcessing: Bool = false
    
    // Vendor Profilleri
    private let profiles: [VendorProfile] = [
        TrendyolProfile(),
        A101Profile(),
        DefaultProfile()
    ]
    
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
            
            // TextBlock'ları oluştur (Spatial Analysis ve Profiling için)
            let textBlocks = self.createTextBlocks(from: observations)
            
            DispatchQueue.main.async {
                self.recognizedText = extractedText
                self.isProcessing = false
                
                // Ham metni anlamlandır ve Invoice objesine çevir
                // Önce Vendor Profillerini dene, olmazsa genel Regex'e düş
                let draftInvoice = self.parseRawTextToInvoice(text: extractedText, blocks: textBlocks)
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
    
    // MARK: - Helper Methods
    
    private func createTextBlocks(from observations: [VNRecognizedTextObservation]) -> [TextBlock] {
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return TextBlock(text: candidate.string, boundingBox: observation.boundingBox)
        }
    }
    
    // MARK: - Parsing Logic
    
    /// Ham metni ve blokları analiz edip Fatura objesine dönüştürür.
    private func parseRawTextToInvoice(text: String, blocks: [TextBlock]) -> Invoice {
        // 1. Adım: Genel Regex Analizi (InvoiceParser)
        // Önce genel kurallarla bir taslak oluşturuyoruz.
        var invoice = InvoiceParser.shared.parse(text: text)
        
        // 2. Adım: Vendor Profiling (Strategy Pattern)
        // Satıcıyı tanı ve ona özel kuralları uygula.
        let textLowercased = text.lowercased()
        
        for profile in profiles {
            // DefaultProfile en sonda olmalı veya mantık ona göre kurulmalı.
            // Ancak burada listeyi sırayla geziyoruz.
            // DefaultProfile her şeye uyduğu için en sona koymak mantıklı, 
            // ama burada 'ilk eşleşen' mantığı yerine 'uygun olanı uygula' diyebiliriz.
            // Fakat genelde tek bir satıcı olur.
            
            if profile.applies(to: textLowercased) {
                print("OCRService: Tespit edilen satıcı profili: \(profile.vendorName)")
                profile.applyRules(to: &invoice, rawText: text)
                
                // Eğer DefaultProfile değilse döngüden çıkabiliriz (Strategy seçildi)
                if !(profile is DefaultProfile) {
                    break
                }
            }
        }
        
        return invoice
    }
    
    /// Faturadaki eksik alanları genel regex kurallarıyla doldurur.
    // Bu metod artık kullanılmıyor çünkü InvoiceParser ana parser oldu.
    // private func completeInvoiceWithFallback... (Silindi)

    
    // MARK: - Helper Regex Functions
    // Regex fonksiyonları InvoiceParser sınıfına taşındı.

