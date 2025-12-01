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
        
        // 1. Toplam Tutar Bulma
        if invoice.totalAmount == 0.0 {
            if let total = extractDouble(from: text, regex: "(?i)TOPLAM[:\\s]*([\\d.,]+)") {
                invoice.totalAmount = total
            }
        }
        
        // 2. Tarih Bulma
        // Profil bulamadıysa veya yanlış bulduysa tekrar bakılabilir (Opsiyonel)
        // Şimdilik sadece boşsa dolduruyoruz.
        // Not: Date optional değil, varsayılan Date() var. O yüzden kontrolü nasıl yapacağımız önemli.
        // Varsayılan tarih bugünün tarihi ise ve biz regex ile başka bir tarih bulursak değiştirelim.
        if Calendar.current.isDateInToday(invoice.invoiceDate) { // Basit bir kontrol
             if let date = extractDate(from: text) {
                 invoice.invoiceDate = date
             }
        }
        
        // 3. Vergi No / TCKN Bulma
        if invoice.merchantTaxID.isEmpty {
            if let taxId = extractString(from: text, regex: "\\b[0-9]{10,11}\\b") {
                invoice.merchantTaxID = taxId
            }
        }
        
        return invoice
    }
    
    // MARK: - Helper Regex Functions
    
    private func extractDouble(from text: String, regex: String) -> Double? {
        guard let range = text.range(of: regex, options: .regularExpression) else { return nil }
        let match = String(text[range])
        
        // Sadece sayısal kısmı al (regex grubunu yakalamak daha iyi olurdu ama basitçe yapalım)
        // Regex grubunu almak için NSRegularExpression kullanmak daha sağlıklı.
        
        do {
            let regexObj = try NSRegularExpression(pattern: regex, options: [])
            let nsString = text as NSString
            let results = regexObj.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            if let first = results.first, first.numberOfRanges > 1 {
                let range = first.range(at: 1) // 1. Grup (Sayı kısmı)
                let numberString = nsString.substring(with: range)
                
                // Format düzeltme: 1.250,00 -> 1250.00
                // veya 1,250.00 -> 1250.00
                // Türkiye standardı: Nokta binlik, Virgül ondalık.
                
                let cleanedString = numberString.replacingOccurrences(of: ".", with: "")
                                                .replacingOccurrences(of: ",", with: ".")
                
                return Double(cleanedString)
            }
        } catch {
            print("Regex hatası: \(error)")
        }
        
        return nil
    }
    
    private func extractDate(from text: String) -> Date? {
        // Regex: dd.MM.yyyy veya dd/MM/yyyy
        let regex = #"(\d{2}[./-]\d{2}[./-]\d{4})"#
        guard let range = text.range(of: regex, options: .regularExpression) else { return nil }
        let dateString = String(text[range])
        
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy" // Varsayılan deneme
        if let date = formatter.date(from: dateString) { return date }
        
        formatter.dateFormat = "dd/MM/yyyy"
        if let date = formatter.date(from: dateString) { return date }
        
        formatter.dateFormat = "dd-MM-yyyy"
        if let date = formatter.date(from: dateString) { return date }
        
        return nil
    }
    
    private func extractString(from text: String, regex: String) -> String? {
        guard let range = text.range(of: regex, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}
