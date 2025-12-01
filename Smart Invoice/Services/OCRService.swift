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
    private let profiles: [VendorProfileProtocol] = [
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
        // 1. Adım: Vendor Profiling (Strategy Pattern)
        // Eğer bir satıcı profili eşleşirse, onun parsing mantığını kullan.
        for profile in profiles {
            if profile.isMatch(text: text) {
                print("OCRService: Tespit edilen satıcı profili: \(profile.vendorName)")
                if let invoice = profile.parse(textBlocks: blocks) {
                    // Profil başarılı bir şekilde parse ettiyse döndür
                    // Ancak eksik alanlar varsa aşağıda genel regex ile tamamlayabiliriz (Hybrid yaklaşım)
                    return completeInvoiceWithFallback(invoice, text: text)
                }
            }
        }
        
        print("OCRService: Satıcı profili eşleşmedi, genel Regex analizi yapılıyor.")
        
        // 2. Adım: Fallback (Genel Regex Analizi)
        var invoice = Invoice(userId: "")
        return completeInvoiceWithFallback(invoice, text: text)
    }
    
    /// Faturadaki eksik alanları genel regex kurallarıyla doldurur.
    private func completeInvoiceWithFallback(_ partialInvoice: Invoice, text: String) -> Invoice {
        var invoice = partialInvoice
        
        // InvoiceParser (Regex Motoru) ile tam bir analiz yap
        let regexInvoice = InvoiceParser.shared.parse(text: text)
        
        // Eksik alanları Regex sonucuyla doldur
        if invoice.totalAmount == 0.0 {
            invoice.totalAmount = regexInvoice.totalAmount
        }
        
        // Tarih kontrolü: Eğer mevcut tarih bugün ise (varsayılan) ve regex farklı bir tarih bulduysa
        if Calendar.current.isDateInToday(invoice.invoiceDate) && !Calendar.current.isDateInToday(regexInvoice.invoiceDate) {
            invoice.invoiceDate = regexInvoice.invoiceDate
        }
        
        if invoice.merchantTaxID.isEmpty {
            invoice.merchantTaxID = regexInvoice.merchantTaxID
        }
        
        if invoice.invoiceNo.isEmpty {
            invoice.invoiceNo = regexInvoice.invoiceNo
        }
        
        if invoice.ettn.isEmpty {
            invoice.ettn = regexInvoice.ettn
        }
        
        if invoice.merchantName.isEmpty {
            invoice.merchantName = regexInvoice.merchantName
        }
        
        // Güven skorunu güncelle
        invoice.confidenceScore = max(invoice.confidenceScore, regexInvoice.confidenceScore)
        
        return invoice
    }
    
    // MARK: - Helper Regex Functions
    // Regex fonksiyonları InvoiceParser sınıfına taşındı.

