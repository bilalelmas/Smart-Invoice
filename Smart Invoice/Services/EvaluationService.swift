import Foundation
import UIKit
import Combine

/// Doğruluk Ölçümü ve Test Servisi (Faz 4)
/// Golden Dataset ile OCR sonuçlarını karşılaştırır.
class EvaluationService: ObservableObject {
    
    @Published var results: [EvaluationResult] = []
    @Published var overallScore: Double = 0.0
    @Published var isRunning: Bool = false
    
    private let ocrService = OCRService()
    
    struct GoldenRecord: Codable {
        let id: String
        let fileName: String
        let expected: ExpectedData
    }
    
    struct ExpectedData: Codable {
        let merchantName: String
        let totalAmount: Double
        let date: String
        let taxID: String
    }
    
    struct EvaluationResult: Identifiable {
        let id = UUID()
        let fileName: String
        let score: Double
        let details: String
        let isSuccess: Bool
    }
    
    /// Testi Başlat
    func runEvaluation() {
        self.isRunning = true
        self.results = []
        
        // 1. Golden Dataset'i Yükle
        guard let url = Bundle.main.url(forResource: "GoldenDataset", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([GoldenRecord].self, from: data) else {
            print("❌ GoldenDataset.json bulunamadı veya okunamadı.")
            self.isRunning = false
            return
        }
        
        let group = DispatchGroup()
        var tempResults: [EvaluationResult] = []
        
        for record in records {
            group.enter()
            
            // 2. Görseli Yükle (Assets veya Bundle'dan)
            // Not: Gerçek test için bu isimde görsellerin projeye eklenmesi gerekir.
            guard let image = UIImage(named: record.fileName) else {
                print("⚠️ Görsel bulunamadı: \(record.fileName)")
                tempResults.append(EvaluationResult(fileName: record.fileName, score: 0, details: "Görsel Bulunamadı", isSuccess: false))
                group.leave()
                continue
            }
            
            // 3. OCR Çalıştır
            ocrService.recognizeText(from: image) { invoice in
                guard let invoice = invoice else {
                    tempResults.append(EvaluationResult(fileName: record.fileName, score: 0, details: "OCR Başarısız", isSuccess: false))
                    group.leave()
                    return
                }
                
                // 4. Karşılaştır ve Puanla
                let score = self.calculateScore(expected: record.expected, actual: invoice)
                let isSuccess = score > 80.0
                let details = "Beklenen: \(record.expected.totalAmount) TL, Bulunan: \(invoice.totalAmount) TL"
                
                tempResults.append(EvaluationResult(fileName: record.fileName, score: score, details: details, isSuccess: isSuccess))
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            self.results = tempResults
            self.overallScore = tempResults.isEmpty ? 0 : tempResults.reduce(0) { $0 + $1.score } / Double(tempResults.count)
            self.isRunning = false
        }
    }
    
    private func calculateScore(expected: ExpectedData, actual: Invoice) -> Double {
        var score = 0.0
        var totalWeight = 0.0
        
        // Tutar (%40 Ağırlık)
        totalWeight += 40
        if abs(expected.totalAmount - actual.totalAmount) < 0.01 {
            score += 40
        }
        
        // Vergi No (%30 Ağırlık)
        totalWeight += 30
        if expected.taxID == actual.merchantTaxID {
            score += 30
        }
        
        // Satıcı Adı (%20 Ağırlık)
        totalWeight += 20
        if actual.merchantName.uppercased().contains(expected.merchantName.uppercased()) {
            score += 20
        }
        
        // Tarih (%10 Ağırlık)
        totalWeight += 10
        // Tarih karşılaştırması (String -> Date dönüşümü basitleştirildi)
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        if let expectedDate = formatter.date(from: expected.date),
           Calendar.current.isDate(expectedDate, inSameDayAs: actual.invoiceDate) {
            score += 10
        }
        
        return score
    }
}
