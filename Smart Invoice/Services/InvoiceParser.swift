import Foundation

/// Ham OCR metnini analiz edip yapılandırılmış Fatura verisine çeviren sınıf.
/// Python projesindeki 'FaturaAnalizMotoru' ve 'ProfileRule' mantığının Swift uyarlamasıdır.
class InvoiceParser {
    
    static let shared = InvoiceParser()
    
    // Mevcut profilleri listeye ekliyoruz
    private let profiles: [VendorProfile] = [
        TrendyolProfile(),
        A101Profile(),
        FLOProfile()
    ]
    
    private init() {}
    
    /// OCR'dan gelen ham metni işler ve Fatura objesi döndürür.
    /// - Parameter text: Vision framework'ten gelen ham metin string'i.
    func parse(text: String) -> Invoice {
        var invoice = Invoice(userId: "") // Kullanıcı ID sonradan set edilecek
        
        // 1. Temel Regex ile Veri Çıkarma
        invoice.merchantName = extractMerchantName(from: text)
        invoice.invoiceNo = extractInvoiceNumber(from: text)
        invoice.invoiceDate = extractDate(from: text)
        invoice.ettn = extractETTN(from: text)
        invoice.merchantTaxID = extractTaxID(from: text)
        invoice.totalAmount = extractTotalAmount(from: text)
        
        // 2. VENDOR PROFILING (STRATEGY PATTERN)
        // Metni küçük harfe çevirip profilleri kontrol et
        let textLower = text.lowercased()
        
        for profile in profiles {
            if profile.applies(to: textLower) {
                print("✅ Tespit Edilen Satıcı Profili: \(profile.vendorName)")
                // Profile özel kuralları uygula
                profile.applyRules(to: &invoice, rawText: text)
                break // İlk eşleşen profili uygula ve çık
            }
        }
        
        // 3. Güven Skoru Hesapla
        invoice.confidenceScore = calculateConfidence(invoice: invoice)
        
        return invoice
    }
    
    // MARK: - Regex Helpers
    
    /// Fatura Numarasını Bulur (Örn: GIB2023000000169)
    /// Standart e-Arşiv Formatı: 3 Karakter Prefix + Yıl + 9 Rakam
    private func extractInvoiceNumber(from text: String) -> String {
        // Regex: 3 Büyük harf, ardından 20 ile başlayan yıl, ardından rakamlar
        let pattern = "[A-Z]{3}20[0-9]{2}[0-9]{9}"
        return extractString(from: text, pattern: pattern) ?? ""
    }
    
    /// ETTN (UUID) Bulur (Örn: 5D5337B3-19D5-1EDD-B7CA-1CE168725B20)
    private func extractETTN(from text: String) -> String {
        let pattern = "[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}"
        return extractString(from: text, pattern: pattern) ?? ""
    }
    
    /// Tarih Bulur (Formatlar: dd.mm.yyyy, dd-mm-yyyy, dd/mm/yyyy)
    private func extractDate(from text: String) -> Date {
        // Regex: Gün (01-31) . Ay (01-12) . Yıl (20xx)
        let pattern = "\\b(0[1-9]|[12][0-9]|3[01])[-./](0[1-9]|1[012])[-./](20\\d{2})\\b"
        
        if let dateString = extractString(from: text, pattern: pattern) {
            // String'i Date objesine çevir (Formatları normalize et)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "tr_TR")
            
            let formats = ["dd.MM.yyyy", "dd-MM-yyyy", "dd/MM/yyyy"]
            for format in formats {
                formatter.dateFormat = format
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
        }
        return Date() // Bulunamazsa bugünü döndür
    }
    
    /// Vergi Kimlik Numarası (VKN) veya TCKN bulur (10 veya 11 hane)
    private func extractTaxID(from text: String) -> String {
        // Genelde "VKN:", "Vergi No:" gibi ön ekler olur ama bazen sadece numara yazar.
        // Basitlik için 10 veya 11 haneli sayıları arıyoruz.
        let pattern = "\\b[0-9]{10,11}\\b"
        // Burada geliştirme yapılabilir: Etrafındaki kelimelere bakılabilir.
        return extractString(from: text, pattern: pattern) ?? ""
    }
    
    /// Toplam Tutarı Bulur
    /// Python'daki 'profile_a101.py' dosyasındaki mantığı buraya taşıdık.
    private func extractTotalAmount(from text: String) -> Double {
        // Anahtar kelimeler: Toplam, Ödenecek, Genel Toplam
        // Format: Sayı,Sayı (Türkçe ondalık)
        
        let keyWords = ["GENEL TOPLAM", "ÖDENECEK TUTAR", "TOPLAM TUTAR", "TOPLAM"]
        let lines = text.components(separatedBy: .newlines)
        
        for keyword in keyWords {
            // Tersten tarama yap (Toplam genelde alttadır)
            for line in lines.reversed() {
                let upperLine = line.uppercased()
                if upperLine.contains(keyword) {
                    // Bu satırda sayısal değeri bul
                    // Regex: Sayı nokta veya virgül Sayı
                    if let amountStr = extractString(from: line, pattern: "(\\d+[.,]\\d{2})") {
                        return normalizeAmount(amountStr)
                    }
                }
            }
        }
        return 0.0
    }
    
    /// Satıcı adını tahmin eder
    /// Genelde ilk satırlarda yer alır.
    private func extractMerchantName(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        // İlk 5 satırı kontrol et, "A.Ş.", "LTD.", "TİC." geçen ilk satırı al
        for i in 0..<min(lines.count, 5) {
            let line = lines[i]
            if line.uppercased().contains("A.Ş") || line.uppercased().contains("LTD") || line.uppercased().contains("TİC") {
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Bulunamazsa ilk dolu satırı döndür (Genelde firma adıdır)
        return lines.first { !$0.isEmpty } ?? ""
    }
    
    // MARK: - Utilities
    
    /// Generic Regex String Extractor
    func extractString(from text: String, pattern: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsString = text as NSString
            let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            if let match = results.first {
                // Eğer grup yakalama varsa (parenthesis), ilk grubu döndür
                if match.numberOfRanges > 1 {
                    return nsString.substring(with: match.range(at: 1))
                }
                return nsString.substring(with: match.range)
            }
        } catch {
            print("Regex Hatası: \(error)")
        }
        return nil
    }
    
    /// "1.250,50" -> 1250.50 çevrimi yapar
    func normalizeAmount(_ amountStr: String) -> Double {
        // Binlik ayracı (.) kaldır, ondalık ayracı (,) nokta yap
        var cleanStr = amountStr.replacingOccurrences(of: ".", with: "")
        cleanStr = cleanStr.replacingOccurrences(of: ",", with: ".")
        return Double(cleanStr) ?? 0.0
    }
    
    /// Basit güven skoru hesabı
    private func calculateConfidence(invoice: Invoice) -> Float {
        var score: Float = 0.0
        if !invoice.invoiceNo.isEmpty { score += 0.3 }
        if invoice.totalAmount > 0 { score += 0.3 }
        if invoice.invoiceDate < Date() { score += 0.2 } // Gelecek tarihli olamaz
        if !invoice.merchantName.isEmpty { score += 0.2 }
        return score
    }
}
