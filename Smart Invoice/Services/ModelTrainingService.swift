import Foundation
import FirebaseFirestore

/// TrainingData'yı analiz edip model iyileştirmeleri yapan servis
/// Active Learning mekanizmasının merkezidir
class ModelTrainingService {
    private let db = Firestore.firestore()
    
    /// Tüm training data'yı Firebase'den çeker ve analiz eder
    func analyzeTrainingData() async throws -> TrainingAnalysis {
        let snapshot = try await db.collection("training_data")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        let allTrainingData = try snapshot.documents.compactMap { document in
            try document.data(as: TrainingData.self)
        }
        
        return analyzeData(allTrainingData)
    }
    
    /// Training data'yı analiz eder ve iyileştirme önerileri üretir
    private func analyzeData(_ trainingData: [TrainingData]) -> TrainingAnalysis {
        var fieldErrors: [String: Int] = [:] // Hangi alan ne kadar hata yapıyor
        var patternSuggestions: [PatternSuggestion] = []
        var confidenceAdjustments: [String: Double] = [:]
        
        // 1. Hangi alanların en çok hata yaptığını bul
        for data in trainingData {
            for field in data.diffs {
                fieldErrors[field, default: 0] += 1
            }
        }
        
        // 2. En çok hata yapan alanları tespit et
        let sortedErrors = fieldErrors.sorted { $0.value > $1.value }
        
        // 3. Her alan için pattern önerileri oluştur
        for (field, errorCount) in sortedErrors {
            let relevantData = trainingData.filter { $0.diffs.contains(field) }
            
            // Örnek: totalAmount için yeni pattern önerileri
            if field == "totalAmount" {
                let suggestions = analyzeAmountPatterns(relevantData)
                patternSuggestions.append(contentsOf: suggestions)
            }
            
            // Örnek: merchantName için yeni pattern önerileri
            if field == "merchantName" {
                let suggestions = analyzeMerchantNamePatterns(relevantData)
                patternSuggestions.append(contentsOf: suggestions)
            }
            
            // Confidence score ayarlamaları
            // Eğer bir alan çok hata yapıyorsa, confidence threshold'unu düşür
            let errorRate = Double(errorCount) / Double(trainingData.count)
            if errorRate > 0.1 { // %10'dan fazla hata varsa
                confidenceAdjustments[field] = 0.1 - errorRate // Confidence'ı düşür
            }
        }
        
        return TrainingAnalysis(
            totalSamples: trainingData.count,
            fieldErrors: fieldErrors,
            patternSuggestions: patternSuggestions,
            confidenceAdjustments: confidenceAdjustments,
            mostErrorProneFields: Array(sortedErrors.prefix(5).map { $0.key })
        )
    }
    
    /// Tutar pattern'lerini analiz eder
    private func analyzeAmountPatterns(_ data: [TrainingData]) -> [PatternSuggestion] {
        var suggestions: [PatternSuggestion] = []
        
        // OCR'ın yanlış okuduğu tutarları analiz et
        for trainingData in data {
            let original = trainingData.originalOCR.totalAmount
            let corrected = trainingData.userCorrected.totalAmount
            
            // Eğer tutar tamamen yanlışsa (örn: 100 yerine 1000)
            if abs(original - corrected) > original * 0.5 {
                // Yeni pattern önerisi: Daha sıkı regex kontrolü
                let currentPattern = RegexPatterns.Amount.flexible
                let suggestedPattern = "\\b\\d{1,3}(?:\\.\\d{3})*(?:[.,]\\d{1,2})?\\s*(?:TL|₺)?\\b(?<!202[0-9])" // Yıl kontrolü eklenmiş
                suggestions.append(PatternSuggestion(
                    field: "totalAmount",
                    currentPattern: currentPattern,
                    suggestedPattern: suggestedPattern,
                    reason: "Yıl ile tutar karışması tespit edildi",
                    confidence: 0.7
                ))
            }
        }
        
        return suggestions
    }
    
    /// Satıcı adı pattern'lerini analiz eder
    private func analyzeMerchantNamePatterns(_ data: [TrainingData]) -> [PatternSuggestion] {
        var suggestions: [PatternSuggestion] = []
        
        // OCR'ın yanlış okuduğu satıcı adlarını analiz et
        for trainingData in data {
            let original = trainingData.originalOCR.merchantName
            let corrected = trainingData.userCorrected.merchantName
            
            // Eğer satıcı adı tamamen farklıysa
            if original.lowercased() != corrected.lowercased() {
                // Yeni keyword önerisi
                if !corrected.isEmpty {
                    suggestions.append(PatternSuggestion(
                        field: "merchantName",
                        currentPattern: "N/A",
                        suggestedPattern: "Yeni keyword: \(corrected.prefix(20))",
                        reason: "Yeni satıcı adı pattern'i tespit edildi",
                        confidence: 0.6
                    ))
                }
            }
        }
        
        return suggestions
    }
    
    /// Training data'yı CSV formatında export eder (Python model eğitimi için)
    func exportTrainingDataToCSV() async throws -> String {
        let snapshot = try await db.collection("training_data")
            .getDocuments()
        
        let allTrainingData = try snapshot.documents.compactMap { document in
            try document.data(as: TrainingData.self)
        }
        
        var csv = "invoice_id,field,original_value,corrected_value,diff_type,created_at\n"
        
        for data in allTrainingData {
            for field in data.diffs {
                let originalValue: String
                let correctedValue: String
                
                switch field {
                case "merchantName":
                    originalValue = data.originalOCR.merchantName
                    correctedValue = data.userCorrected.merchantName
                case "totalAmount":
                    originalValue = String(data.originalOCR.totalAmount)
                    correctedValue = String(data.userCorrected.totalAmount)
                case "taxAmount":
                    originalValue = String(data.originalOCR.taxAmount)
                    correctedValue = String(data.userCorrected.taxAmount)
                case "invoiceNo":
                    originalValue = data.originalOCR.invoiceNo
                    correctedValue = data.userCorrected.invoiceNo
                case "ettn":
                    originalValue = data.originalOCR.ettn
                    correctedValue = data.userCorrected.ettn
                default:
                    continue
                }
                
                csv += "\(data.invoiceId),\(field),\"\(originalValue)\",\"\(correctedValue)\",\(field),\(data.createdAt)\n"
            }
        }
        
        return csv
    }
}

// MARK: - Analysis Models

struct TrainingAnalysis {
    let totalSamples: Int
    let fieldErrors: [String: Int] // Hangi alan kaç hata yapmış
    let patternSuggestions: [PatternSuggestion]
    let confidenceAdjustments: [String: Double]
    let mostErrorProneFields: [String] // En çok hata yapan alanlar
}

struct PatternSuggestion {
    let field: String
    let currentPattern: String
    let suggestedPattern: String
    let reason: String
    let confidence: Double // Önerinin güvenilirliği (0-1)
}

