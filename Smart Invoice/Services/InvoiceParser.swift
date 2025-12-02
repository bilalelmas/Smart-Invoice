import Foundation

class InvoiceParser {
    
    static let shared = InvoiceParser()
    private init() {}
    
    // Satıcı profillerini burada tutuyoruz
    private let profiles: [VendorProfile] = [
        TrendyolProfile(),
        A101Profile(),
        FLOProfile()
    ]
    
    func parse(text: String) -> Invoice {
        var invoice = Invoice(userId: "")
        let cleanText = text.uppercased() // Büyük harf normalizasyonu
        
        // 1. Temel Veriler
        invoice.invoiceNo = extractInvoiceNumber(from: cleanText)
        invoice.invoiceDate = extractDate(from: cleanText)
        invoice.ettn = extractETTN(from: cleanText)
        invoice.merchantName = extractMerchantName(from: text) // Orijinal text kullan (Büyük/Küçük harf bozulmasın)
        invoice.merchantTaxID = extractTaxID(from: cleanText)
        
        // 2. Gelişmiş Tutar Algoritmaları (Analiz edilen faturalara göre)
        invoice.totalAmount = extractTotalAmount(from: cleanText)
        invoice.taxAmount = extractTaxAmount(from: cleanText)
        
        // 3. Vendor Profiling (Satıcıya özel düzeltmeler)
        let textLower = text.lowercased()
        for profile in profiles {
            if profile.applies(to: textLower) {
                print("✅ Profil Uygulandı: \(profile.vendorName)")
                profile.applyRules(to: &invoice, rawText: text)
                break
            }
        }
        
        // 4. Güven Skoru
        invoice.confidenceScore = calculateConfidence(invoice: invoice)
        
        return invoice
    }
    
    // MARK: - Gelişmiş Tutar Çıkarma Mantığı
    
    /// Toplam tutarı bulmak için faturayı sondan başa doğru tarar.
    /// Örnekler: "ÖDENECEK TUTAR 319,90TL", "GENEL TOPLAM 1.664,90"
    internal func extractTotalAmount(from text: String) -> Double {
        // En güçlü anahtar kelimelerden en zayıfa doğru sıralı
        let keywords = [
            "ÖDENECEK TUTAR",
            "ODENECEK TUTAR",
            "GENEL TOPLAM",
            "TOPLAM TUTAR",
            "VERGILER DAHIL TOPLAM",
            "VERGİLER DAHİL TOPLAM TUTAR"
        ]
        
        let lines = text.components(separatedBy: .newlines)
        
        // Faturanın alt kısımlarına bakmak için tersten döngü (Reverse Loop)
        for line in lines.reversed() {
            for keyword in keywords {
                if line.contains(keyword) {
                    // Anahtar kelimeyi bulduk, şimdi sayı avına çıkalım
                    if let amount = findAmountInString(line) {
                        return amount
                    }
                }
            }
        }
        
        // Eğer satırda bulamazsa, anahtar kelimenin hemen altındaki satıra bak (Bazen kayma olur)
        for (index, line) in lines.enumerated().reversed() {
            for keyword in keywords {
                if line.contains(keyword) {
                    // Bir sonraki satıra bak (Array bounds kontrolü ile)
                    if index + 1 < lines.count {
                        if let amount = findAmountInString(lines[index + 1]) {
                            return amount
                        }
                    }
                }
            }
        }
        
        return 0.0
    }
    
    /// KDV Tutarını Bulur
    internal func extractTaxAmount(from text: String) -> Double {
        let keywords = [
            "HESAPLANAN KDV",
            "TOPLAM KDV",
            "KDV TUTARI",
            "HESAPLANAN KATMA DEĞER VERGİSİ", // Teknosa örneği
            "KDV (%18)",
            "KDV (%20)",
            "KDV (%10)"
        ]
        
        let lines = text.components(separatedBy: .newlines)
        
        // KDV genelde toplam tutarın biraz üstündedir, yine tersten bakmak mantıklı
        for line in lines.reversed() {
            for keyword in keywords {
                if line.contains(keyword) {
                    if let amount = findAmountInString(line) {
                        return amount
                    }
                }
            }
        }
        return 0.0
    }
    
    // MARK: - Regex Yardımcıları
    
    /// Bir metin satırının içindeki para miktarını çekip Double'a çevirir.
    /// "1.664,90TL" -> 1664.90
    /// "319,90 TRY" -> 319.90
    private func findAmountInString(_ text: String) -> Double? {
        // 1. Temizlik: Harfleri ve boşlukları at, sadece sayı ve ayraç kalsın
        // Örn: "1.664,90TL" -> "1.664,90"
        let pattern = "[0-9.,]+"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let results = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            
            // Satırdaki en son sayıyı almak genelde doğrudur (Örn: "%18 30,36" -> 30.36'yı almak için)
            if let lastMatch = results.last, let range = Range(lastMatch.range, in: text) {
                let amountStr = String(text[range])
                return normalizeAmount(amountStr)
            }
        } catch {
            print("Regex Hatası: \(error)")
        }
        return nil
    }
    
    /// Türk Lirası formatını (1.000,50) sisteme (1000.50) çevirir.
    internal func normalizeAmount(_ amountStr: String) -> Double {
        var cleanStr = amountStr
        
        // Sadece nokta ve virgül ve sayı kalsın
        cleanStr = cleanStr.replacingOccurrences(of: "[^0-9.,]", with: "", options: .regularExpression)
        
        // Eğer hem nokta hem virgül varsa (1.664,90 gibi)
        if cleanStr.contains(".") && cleanStr.contains(",") {
            // Noktaları (binlik ayracı) sil
            cleanStr = cleanStr.replacingOccurrences(of: ".", with: "")
            // Virgülü (ondalık) noktaya çevir
            cleanStr = cleanStr.replacingOccurrences(of: ",", with: ".")
        }
        // Sadece virgül varsa (319,90 gibi) -> (319.90) yap
        else if cleanStr.contains(",") {
            cleanStr = cleanStr.replacingOccurrences(of: ",", with: ".")
        }
        // Sadece nokta varsa ve sonda 2 hane varsa (319.90 gibi) -> Dokunma
        // Sadece nokta var ve sonda 3 hane varsa (1.000 gibi) -> Noktayı sil
        
        return Double(cleanStr) ?? 0.0
    }
    
    internal func extractString(from text: String, pattern: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsString = text as NSString
            let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            if let match = results.first {
                return nsString.substring(with: match.range)
            }
        } catch { return nil }
        return nil
    }

    private func extractInvoiceNumber(from text: String) -> String {
        // Standart 16 haneli (3 harf 13 sayı) veya ETTN formatı
        // Örn: GIB2023000000169 veya N012024...
        let pattern = "[A-Z0-9]{3}20[0-9]{2}[0-9]{9}"
        if let num = extractString(from: text, pattern: pattern) { return num }
        
        // Alternatif kısa formatlar için (Bazı e-arşivler)
        return extractString(from: text, pattern: "\\b[A-Z]{3}[0-9]{13}\\b") ?? ""
    }
    
    private func extractETTN(from text: String) -> String {
        return extractString(from: text, pattern: "[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}") ?? ""
    }
    
    private func extractDate(from text: String) -> Date {
        // dd/mm/yyyy, dd.mm.yyyy, dd-mm-yyyy formatları
        let pattern = "\\b(0[1-9]|[12][0-9]|3[01])[-./](0[1-9]|1[012])[-./](20\\d{2})\\b"
        if let dateStr = extractString(from: text, pattern: pattern) {
            let formatter = DateFormatter()
            let formats = ["dd.MM.yyyy", "dd-MM-yyyy", "dd/MM/yyyy"]
            for f in formats {
                formatter.dateFormat = f
                if let date = formatter.date(from: dateStr) { return date }
            }
        }
        return Date()
    }
    
    private func extractMerchantName(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        // İlk satırlarda A.Ş, LTD, TİC arayalım
        for i in 0..<min(lines.count, 6) {
            let line = lines[i].uppercased()
            if line.contains("A.Ş") || line.contains("LTD") || line.contains("TİC") || line.contains("SAN") {
                return lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Bulamazsak ilk dolu satırı al (Genelde firma adıdır)
        return lines.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }
    
    private func extractTaxID(from text: String) -> String {
        // VKN: veya TCKN: kelimelerinden sonraki 10-11 haneli sayı
        // Regex: (VKN|TCKN|VERGİ NO)[:\s]*([0-9]{10,11})
        let pattern = "(?:VKN|TCKN|VERGİ NO|VERGI NO)[:\\s]*([0-9]{10,11})"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsString = text as NSString
            let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            if let match = results.first, match.numberOfRanges > 1 {
                 return nsString.substring(with: match.range(at: 1))
            }
        } catch {}
        
        // Etiketsiz sadece 10-11 hane bulmayı dene (Son çare)
        return extractString(from: text, pattern: "\\b[0-9]{10,11}\\b") ?? ""
    }
    
    private func calculateConfidence(invoice: Invoice) -> Float {
        var score: Float = 0.0
        if !invoice.invoiceNo.isEmpty { score += 0.3 }
        if invoice.totalAmount > 0 { score += 0.4 } // Tutar en önemlisi
        if !invoice.merchantName.isEmpty { score += 0.2 }
        if invoice.taxAmount > 0 { score += 0.1 }
        return score
    }
}
