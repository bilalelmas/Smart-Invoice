import Foundation

/// OCR servisi için özel hata tipleri
enum OCRServiceError: LocalizedError {
    case imageError(String)
    case recognitionError(String)
    case processingError(String)
    case invalidImage
    
    var errorDescription: String? {
        switch self {
        case .imageError(let message):
            return "Görüntü Hatası: \(message)"
        case .recognitionError(let message):
            return "Metin Tanıma Hatası: \(message)"
        case .processingError(let message):
            return "İşleme Hatası: \(message)"
        case .invalidImage:
            return "Geçersiz görüntü formatı"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .imageError:
            return "Görüntü işlenemedi"
        case .recognitionError:
            return "OCR işlemi başarısız oldu"
        case .processingError:
            return "Veri işleme sırasında hata oluştu"
        case .invalidImage:
            return "Görüntü formatı desteklenmiyor"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .imageError, .invalidImage:
            return "Lütfen farklı bir görüntü deneyin"
        case .recognitionError:
            return "Görüntü kalitesini kontrol edin ve tekrar deneyin"
        case .processingError:
            return "Lütfen tekrar deneyin"
        }
    }
}

