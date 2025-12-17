import Foundation
import CoreGraphics

/// InvoiceParser için yardımcı fonksiyonlar
/// Regex, tarih, tutar ve ETTN işlemleri için utility fonksiyonları içerir
enum InvoiceParserHelper {
    
    // MARK: - Regex Helper Functions
    
    /// Metinden regex pattern ile string çıkarır
    static func extractString(from text: String, pattern: String) -> String? {
        guard let regex = RegexPatterns.getRegex(pattern: pattern, options: .caseInsensitive) else { return nil }
        let res = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        if let m = res.first, let range = Range(m.range, in: text) {
            return String(text[range])
        }
        return nil
    }
    
    /// Metinden regex pattern ile son eşleşmeyi çıkarır
    static func extractLastMatch(from text: String, pattern: String) -> String? {
        guard let regex = RegexPatterns.getRegex(pattern: pattern) else { return nil }
        let results = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        if let lastMatch = results.last, let range = Range(lastMatch.range, in: text) {
            return String(text[range])
        }
        return nil
    }
    
    // MARK: - Amount Helper Functions
    
    /// Tutar string'ini Double'a çevirir (normalize eder)
    static func normalizeAmount(_ amountStr: String) -> Double {
        var s = amountStr.replacingOccurrences(of: "[^0-9.,]", with: "", options: .regularExpression)
        if s.contains(".") && s.contains(",") { 
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") 
        } else if s.contains(",") { 
            s = s.replacingOccurrences(of: ",", with: ".") 
        }
        return Double(s) ?? 0.0
    }
    
    /// String içinde tutar bulur (yıl kontrolü ile)
    static func findAmountInString(_ text: String) -> Double? {
        if let match = extractString(from: text, pattern: RegexPatterns.Amount.flexible) {
            // Yıl kontrolü (2024, 2025 karışmasın)
            if match.count == 4 && (match.starts(with: "202")) { return nil }
            return normalizeAmount(match)
        }
        return nil
    }
    
    /// String içindeki tüm tutarları bulur
    static func findAllAmountsInString(_ text: String) -> [Double] {
        var amounts: [Double] = []
        guard let regex = RegexPatterns.getRegex(pattern: RegexPatterns.Amount.flexible) else { return [] }
        
        let results = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for result in results {
            if let range = Range(result.range, in: text) {
                let matchString = String(text[range])
                // Yıl kontrolü
                if matchString.count == 4 && matchString.starts(with: "202") { continue }
                let amount = normalizeAmount(matchString)
                if amount > 0 {
                    amounts.append(amount)
                }
            }
        }
        return amounts
    }
    
    // MARK: - ETTN Helper Functions
    
    /// ETTN'i standart UUID formatına çevirir
    static func formatETTN(_ text: String) -> String {
        // Boşluk ve tireleri temizle
        var cleaned = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
        
        // OCR hatalarını düzelt
        cleaned = cleaned.replacingOccurrences(of: "l", with: "1")
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
        
        // UUID formatına çevir: 8-4-4-4-12
        if cleaned.count == 32 {
            let index1 = cleaned.index(cleaned.startIndex, offsetBy: 8)
            let index2 = cleaned.index(index1, offsetBy: 4)
            let index3 = cleaned.index(index2, offsetBy: 4)
            let index4 = cleaned.index(index3, offsetBy: 4)
            
            let part1 = String(cleaned[..<index1])
            let part2 = String(cleaned[index1..<index2])
            let part3 = String(cleaned[index2..<index3])
            let part4 = String(cleaned[index3..<index4])
            let part5 = String(cleaned[index4...])
            
            return "\(part1)-\(part2)-\(part3)-\(part4)-\(part5)".lowercased()
        }
        
        return ""
    }
    
    /// ETTN string'ini temizler ve formatlar
    static func cleanETTN(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "ETTN", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // OCR hatalarını düzelt
        t = t.replacingOccurrences(of: "l", with: "1")
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
        
        // Eğer UUID formatında değilse, formatla
        if !t.contains("-") && t.count == 32 {
            return formatETTN(t)
        }
        
        return t.lowercased()
    }
    
    /// Metinden ETTN çıkarır
    static func extractETTNFromText(_ text: String) -> String {
        // Esnek ETTN pattern (boşluk ve tire ile)
        let flexibleETTNPattern = "[a-fA-F0-9]{8}[- ]?[a-fA-F0-9]{4}[- ]?[a-fA-F0-9]{4}[- ]?[a-fA-F0-9]{4}[- ]?[a-fA-F0-9]{12}"
        if let raw = extractString(from: text, pattern: flexibleETTNPattern) {
            return cleanETTN(raw)
        }
        
        // Standart UUID pattern
        if let raw = extractString(from: text, pattern: RegexPatterns.ID.ettn) {
            return cleanETTN(raw)
        }
        
        // Eksik UUID parçalarını birleştir (iki satıra bölünmüş)
        // 8-4-4-4-12 formatında parçalar ara
        let parts = text.components(separatedBy: .whitespacesAndNewlines)
        var uuidParts: [String] = []
        
        for part in parts {
            let cleaned = part.replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: "-", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Hex karakter kontrolü
            if cleaned.range(of: "^[a-fA-F0-9]+$", options: .regularExpression) != nil {
                if cleaned.count == 8 || cleaned.count == 4 || cleaned.count == 12 {
                    uuidParts.append(cleaned)
                }
            }
        }
        
        // UUID parçalarını birleştir: 8-4-4-4-12
        if uuidParts.count >= 5 {
            let combined = uuidParts.prefix(5).joined(separator: "")
            if combined.count == 32 {
                return formatETTN(combined)
            }
        }
        
        return ""
    }
    
    // MARK: - Date Helper Functions
    
    /// Tarih string'ini Date'e çevirir (gelecek tarih kontrolü ile)
    static func parseDateString(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR") // Türkçe locale
        f.timeZone = TimeZone.current
        
        // Tarih formatlarını dene
        let formats = ["dd.MM.yyyy", "dd/MM/yyyy", "dd-MM-yyyy", "d.M.yyyy", "d/M/yyyy", "d-M-yyyy"]
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: s) {
                // İyileştirme: Gelecek tarihleri kontrol et (muhtemelen OCR hatası)
                let calendar = Calendar.current
                let now = Date()
                let maxDate = calendar.date(byAdding: .year, value: 1, to: now) ?? now
                
                // Eğer tarih bugünden 1 yıldan fazla ilerideyse, muhtemelen yıl hatası
                if d > maxDate {
                    // Yılı düzelt (örneğin 2025 yerine 2021)
                    let components = calendar.dateComponents([.day, .month, .year], from: d)
                    if let day = components.day, let month = components.month, var year = components.year {
                        // Eğer yıl 2024'ten büyükse ve bugünün yılından büyükse, düzelt
                        let currentYear = calendar.component(.year, from: now)
                        if year > currentYear + 1 {
                            // Muhtemelen OCR hatası, yılı düzelt
                            // Örnek: 2025 -> 2021, 2026 -> 2022
                            year = year - 4 // Genelde 4 yıl fark oluyor (OCR hatası)
                            if let correctedDate = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
                                return correctedDate
                            }
                        }
                    }
                }
                
                return d
            }
        }
        
        // Eğer hiçbiri çalışmazsa bugünün tarihini döndür (fallback)
        return Date()
    }
    
    // MARK: - Validation Helper Functions
    
    /// Telefon numarası kontrolü
    static func isPhoneNumber(_ text: String) -> Bool {
        let c = text.replacingOccurrences(of: " ", with: "")
        return c.hasPrefix("+9") || c.hasPrefix("05") || c.contains("TEL")
    }
    
    // MARK: - Geometry Helper Functions
    
    /// TextLine'ların birleşik dikdörtgenini hesaplar
    static func calculateUnionRect(of lines: [TextLine]) -> CGRect? {
        guard !lines.isEmpty else { return nil }
        let rects = lines.map { $0.frame }
        let minX = rects.map { $0.minX }.min() ?? 0
        let minY = rects.map { $0.minY }.min() ?? 0
        let maxX = rects.map { $0.maxX }.max() ?? 0
        let maxY = rects.map { $0.maxY }.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    // MARK: - Tax Rate Helper Functions
    
    /// KDV oranını tespit eder (%1, %8, %10, %18, %20)
    static func extractTaxRate(from text: String) -> Double {
        let taxRates: [Double] = [0.01, 0.08, 0.10, 0.18, 0.20] // %1, %8, %10, %18, %20
        let upper = text.uppercased()
        
        // KDV oranı pattern'leri
        let ratePatterns = [
            "KDV.*%?\\s*20", "KDV.*%?\\s*18", "KDV.*%?\\s*10", "KDV.*%?\\s*8", "KDV.*%?\\s*1",
            "%20.*KDV", "%18.*KDV", "%10.*KDV", "%8.*KDV", "%1.*KDV",
            "20%.*KDV", "18%.*KDV", "10%.*KDV", "8%.*KDV", "1%.*KDV"
        ]
        
        for (index, pattern) in ratePatterns.enumerated() {
            if let regex = RegexPatterns.getRegex(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(upper.startIndex..., in: upper)
                if regex.firstMatch(in: upper, range: range) != nil {
                    // Pattern index'e göre oranı döndür (büyükten küçüğe)
                    let rateIndex = index % 5
                    return taxRates[rateIndex]
                }
            }
        }
        
        // Sayısal olarak ara (KDV 18, KDV 20, vb.)
        for rate in taxRates.reversed() {
            let rateInt = Int(rate * 100)
            if upper.contains("KDV \(rateInt)") || upper.contains("\(rateInt)%") {
                return rate
            }
        }
        
        return 0.18 // Varsayılan %18
    }
}

