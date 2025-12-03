import Foundation
import CoreGraphics

class InvoiceParser {
    
    static let shared = InvoiceParser()
    private init() {}
    
    private let profiles: [VendorProfile] = [
        TrendyolProfile(),
        A101Profile(),
        FLOProfile()
    ]
    
    func parse(text: String) -> Invoice {
        // Eski yöntem (String bazlı) - Geriye dönük uyumluluk için
        return parse(blocks: [], rawText: text)
    }
    
    /// Konumsal Analiz Motoru (Spatial Analysis Engine)
    /// Blokları koordinatlarına göre satırlara ayırır ve işler.
    func parse(blocks: [TextBlock], rawText: String? = nil) -> Invoice {
        var invoice = Invoice(userId: "")
        
        // 1. Satırları Oluştur (Row Clustering)
        let lines = groupBlocksIntoLines(blocks)
        let textLines = lines.map { $0.text }
        
        // Eğer blok yoksa (eski yöntem), rawText kullan
        let fullText = rawText ?? textLines.joined(separator: "\n")
        let cleanLines = fullText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        // 2. Blok Ayrıştırma
        let sellerBlock = extractSellerBlock(from: cleanLines)
        
        // 3. Veri Çıkarımı
        invoice.merchantName = extractMerchantName(from: sellerBlock)
        invoice.merchantTaxID = extractMerchantTaxID(from: sellerBlock)
        invoice.invoiceDate = extractDate(from: cleanLines)
        invoice.ettn = extractETTN(from: cleanLines, rawText: fullText)
        invoice.invoiceNo = extractInvoiceNumber(from: fullText)
        
        invoice.totalAmount = extractTotalAmount(from: fullText)
        invoice.taxAmount = extractTaxAmount(from: fullText)
        
        // 4. Tablo Analizi (Spatial Table Parsing)
        // Eğer blok verisi varsa, konumsal tablo analizi yap
        if !blocks.isEmpty {
            invoice.items = extractLineItemsSpatial(lines: lines)
        } else {
            invoice.items = extractLineItems(from: cleanLines)
        }
        
        // 5. Profil Uygulama
        let textLower = fullText.lowercased()
        for profile in profiles {
            if profile.applies(to: textLower) {
                print("✅ Profil Devrede: \(profile.vendorName)")
                profile.applyRules(to: &invoice, rawText: fullText)
                break
            }
        }
        
        // 6. Debug Bölgelerini Hesapla (Faz 3)
        if !blocks.isEmpty {
            populateDebugRegions(invoice: &invoice, blocks: blocks, lines: lines)
        }
        
        invoice.confidenceScore = calculateRealConfidence(invoice: invoice)
        return invoice
    }
    
    // MARK: - 🕵️‍♂️ Debug / Görselleştirme
    
    private func populateDebugRegions(invoice: inout Invoice, blocks: [TextBlock], lines: [TextLine]) {
        // 1. Satıcı Bloğu (Kırmızı)
        // Splitter'a kadar olan kısım
        if let splitIndex = lines.firstIndex(where: { line in RegexPatterns.Keywords.splitters.contains(where: { line.text.uppercased().contains($0) }) }) {
            let sellerLines = Array(lines.prefix(splitIndex))
            if let rect = calculateUnionRect(of: sellerLines) {
                invoice.debugRegions.append(OCRRegion(type: .seller, rect: rect))
            }
        } else {
            // Splitter yoksa ilk %20
            let count = max(1, Int(Double(lines.count) * 0.20))
            let sellerLines = Array(lines.prefix(count))
            if let rect = calculateUnionRect(of: sellerLines) {
                invoice.debugRegions.append(OCRRegion(type: .seller, rect: rect))
            }
        }
        
        // 2. Tablo Alanı (Mavi)
        if let headerIndex = lines.firstIndex(where: { line in RegexPatterns.Keywords.tableHeaders.contains(where: { line.text.uppercased().contains($0) }) }) {
            let footerIndex = lines.indices.first(where: { index in index > headerIndex && RegexPatterns.Keywords.tableFooters.contains(where: { lines[index].text.uppercased().contains($0) }) }) ?? lines.count
            
            // Header ve Footer dahil edelim ki sınırları görelim
            let endIndex = min(footerIndex + 1, lines.count)
            let tableLines = Array(lines[headerIndex..<endIndex])
            
            if let rect = calculateUnionRect(of: tableLines) {
                invoice.debugRegions.append(OCRRegion(type: .table, rect: rect))
            }
        }
        
        // 3. Toplam Tutar (Yeşil)
        // Tutarı içeren bloğu bul
        if invoice.totalAmount > 0 {
            // Tam eşleşme veya normalize edilmiş eşleşme ara
            for block in blocks {
                if let amount = findAmountInString(block.text), abs(amount - invoice.totalAmount) < 0.01 {
                    invoice.debugRegions.append(OCRRegion(type: .total, rect: block.frame))
                    // Genelde tek bir yerdedir ama birden fazla varsa (örn: hem altta hem yanda) ilkini veya hepsini alabiliriz.
                    // Şimdilik ilkini alıp çıkalım.
                    break
                }
            }
        }
        
        // 4. Tarih (Sarı)
        // Tarihi içeren bloğu bul
        // Tarih formatı karmaşık olduğu için regex ile eşleşen bloğu bulalım
        let datePattern = RegexPatterns.DateFormat.standard
        for block in blocks {
            if extractString(from: block.text, pattern: datePattern) != nil {
                // Bulunan tarih bizim extract ettiğimiz tarih mi?
                // Basitçe tarih formatına uyan ilk bloğu işaretleyelim (Genelde doğrudur)
                invoice.debugRegions.append(OCRRegion(type: .date, rect: block.frame))
                break 
            }
        }
    }
    
    private func calculateUnionRect(of lines: [TextLine]) -> CGRect? {
        guard !lines.isEmpty else { return nil }
        let rects = lines.map { $0.frame }
        let minX = rects.map { $0.minX }.min() ?? 0
        let minY = rects.map { $0.minY }.min() ?? 0
        let maxX = rects.map { $0.maxX }.max() ?? 0
        let maxY = rects.map { $0.maxY }.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    // MARK: - 📍 Konumsal Analiz Metodları
    
    /// Blokları Y koordinatlarına göre gruplayıp satır (TextLine) oluşturur.
    private func groupBlocksIntoLines(_ blocks: [TextBlock]) -> [TextLine] {
        guard !blocks.isEmpty else { return [] }
        
        // Blokları Y konumuna göre sırala
        let sortedBlocks = blocks.sorted { $0.y > $1.y } // Vision'da Y aşağıdan yukarı artar mı? Genelde 0 sol üsttür ama Vision'da sol alt olabilir.
        // Vision: (0,0) sol alt, (1,1) sağ üst. Yani Y arttıkça yukarı çıkar.
        // Ancak biz TextBlock oluştururken normalleştirilmiş koordinatları nasıl aldığımıza bağlı.
        // VNRecognizedTextObservation boundingBox (0,0) sol alt köşedir.
        // Biz bunu okurken Y'yi ters çevirip çevirmediğimize dikkat etmeliyiz.
        // Şimdilik Vision'ın standart çıktısını varsayalım: Y değeri satırın alt kenarıdır.
        // Üstteki satırın Y değeri daha BÜYÜK olur.
        
        var lines: [TextLine] = []
        var currentLineBlocks: [TextBlock] = []
        
        for block in sortedBlocks {
            if let lastBlock = currentLineBlocks.last {
                // Y farkı çok azsa aynı satırdadır (Tolerans: %1 - %2)
                if abs(block.midY - lastBlock.midY) < 0.02 {
                    currentLineBlocks.append(block)
                } else {
                    // Yeni satıra geç
                    lines.append(TextLine(blocks: currentLineBlocks))
                    currentLineBlocks = [block]
                }
            } else {
                currentLineBlocks = [block]
            }
        }
        
        if !currentLineBlocks.isEmpty {
            lines.append(TextLine(blocks: currentLineBlocks))
        }
        
        return lines
    }
    
    /// Konumsal Tablo Analizi (Sütun Bazlı)
    private func extractLineItemsSpatial(lines: [TextLine]) -> [InvoiceItem] {
        var items: [InvoiceItem] = []
        
        // 1. Tablo Başlığını Bul
        guard let headerIndex = lines.firstIndex(where: { line in
            RegexPatterns.Keywords.tableHeaders.contains(where: { line.text.uppercased().contains($0) })
        }) else { return [] }
        
        // 2. Tablo Bitişini Bul
        let footerIndex = lines.indices.first(where: { index in
            index > headerIndex && RegexPatterns.Keywords.tableFooters.contains(where: { lines[index].text.uppercased().contains($0) })
        }) ?? lines.count
        
        // 3. Satırları İşle
        for i in (headerIndex + 1)..<footerIndex {
            let line = lines[i]
            
            // Satırda en az 2 blok olmalı (Ürün Adı + Fiyat)
            // Veya tek bloksa içinde fiyat olmalı
            if line.blocks.isEmpty { continue }
            
            // Strateji: En sağdaki blok fiyat adayıdır.
            // Vision blokları soldan sağa sıralı verir (TextLine init içinde sıraladık)
            
            if let lastBlock = line.blocks.last,
               let amount = findAmountInString(lastBlock.text) {
                
                // Fiyat bulundu! Geri kalan bloklar ürün adıdır.
                let nameBlocks = line.blocks.dropLast()
                let name = nameBlocks.map { $0.text }.joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Eğer isim boşsa (Sadece fiyat yazan satır), bir önceki satıra ait olabilir mi?
                // Şimdilik sadece dolu isimleri alalım.
                if !name.isEmpty {
                    items.append(InvoiceItem(name: name, quantity: 1, unitPrice: amount, total: amount, taxRate: 18))
                }
            } else {
                // Blok bazlı bulamadıysak, tüm satır metninde regex ara (Fallback)
                if let amount = findAmountInString(line.text) {
                    let name = line.text.replacingOccurrences(of: RegexPatterns.Amount.flexible, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "TL", with: "")
                    
                    if !name.isEmpty {
                        items.append(InvoiceItem(name: name, quantity: 1, unitPrice: amount, total: amount, taxRate: 18))
                    }
                }
            }
        }
        
        return items
    }
    
    // MARK: - Logic with RegexPatterns
    
    internal func extractTotalAmount(from text: String) -> Double {
        let lines = text.components(separatedBy: .newlines)
        var candidates: [Double] = []
        
        for line in lines.reversed() {
            let upper = line.uppercased()
            
            // RegexPatterns'den gelen kara liste
            if RegexPatterns.Keywords.amountBlacklist.contains(where: { upper.contains($0) }) { continue }
            
            // RegexPatterns'den gelen hedef kelimeler
            if RegexPatterns.Keywords.totalAmounts.contains(where: { upper.contains($0) }) {
                if let amount = findAmountInString(line) {
                    candidates.append(amount)
                }
            }
        }
        
        // "Ödenecek" alt satır kontrolü
        for (index, line) in lines.enumerated().reversed() {
            if RegexPatterns.Keywords.totalAmounts.contains(where: { line.uppercased().contains($0) }) {
                 if index + 1 < lines.count {
                     if let amount = findAmountInString(lines[index + 1]) {
                         candidates.append(amount)
                     }
                 }
             }
        }
        
        return candidates.max() ?? 0.0
    }
    
    internal func extractTaxAmount(from text: String) -> Double {
        let lines = text.components(separatedBy: .newlines)
        for line in lines.reversed() {
            let upper = line.uppercased()
            if RegexPatterns.Keywords.taxAmounts.contains(where: { upper.contains($0) }) {
                if let amount = findAmountInString(line) { return amount }
            }
        }
        return 0.0
    }
    
    private func findAmountInString(_ text: String) -> Double? {
        // RegexPatterns.Amount.flexible kullanımı
        if let match = extractString(from: text, pattern: RegexPatterns.Amount.flexible) {
            // Yıl kontrolü (2024, 2025 karışmasın)
            if match.count == 4 && (match.starts(with: "202")) { return nil }
            return normalizeAmount(match)
        }
        return nil
    }

    private func extractMerchantTaxID(from sellerLines: [String]) -> String {
        // 1. Etiketli VKN Ara
        for line in sellerLines {
            if line.uppercased().contains("VKN") || line.uppercased().contains("VERGI") {
                if let id = extractString(from: line, pattern: RegexPatterns.ID.vkn) { return id }
            }
        }
        
        // 2. Etiketli TCKN Ara
        for line in sellerLines {
            if line.uppercased().contains("TCKN") || line.uppercased().contains("TC KIMLIK") {
                if let id = extractString(from: line, pattern: RegexPatterns.ID.tckn) { return id }
            }
        }
        
        // 3. Etiketsiz Ara
        for line in sellerLines {
            let upper = line.uppercased()
            if upper.contains("SICIL") || upper.contains("MERSIS") || isPhoneNumber(line) { continue }
            
            // 10 veya 11 hane (İki deseni birleştiriyoruz)
            if let id = extractString(from: line, pattern: "\\b[0-9]{10,11}\\b") { return id }
        }
        
        return ""
    }
    
    private func extractDate(from lines: [String]) -> Date {
        // Etiketli Arama
        for line in lines {
            let upper = line.uppercased()
            if RegexPatterns.Keywords.dateTargets.contains(where: { upper.contains($0) }) &&
               !RegexPatterns.Keywords.dateBlacklist.contains(where: { upper.contains($0) }) {
                if let d = extractString(from: line, pattern: RegexPatterns.DateFormat.standard) { return parseDateString(d) }
            }
        }
        
        // Genel Arama (Header bölgesinde)
        let limit = min(lines.count, 20)
        for i in 0..<limit {
            let line = lines[i]
            if RegexPatterns.Keywords.dateBlacklist.contains(where: { line.uppercased().contains($0) }) { continue }
            
            if let d = extractString(from: line, pattern: RegexPatterns.DateFormat.standard) {
                return parseDateString(d)
            }
        }
        return Date()
    }
    
    private func extractLineItems(from lines: [String]) -> [InvoiceItem] {
        var items: [InvoiceItem] = []
        
        // Tablo Başlangıcı
        guard let headerIndex = lines.firstIndex(where: { line in
            RegexPatterns.Keywords.tableHeaders.contains(where: { line.uppercased().contains($0) })
        }) else { return [] }
        
        // Tablo Bitişi
        let footerIndex = lines.indices.first(where: { index in
            index > headerIndex && RegexPatterns.Keywords.tableFooters.contains(where: { lines[index].uppercased().contains($0) })
        }) ?? lines.count
        
        // Satır İşleme
        for line in lines[(headerIndex + 1)..<footerIndex] {
            if line.count < 5 { continue }
            
            // Satırdaki SON fiyatı bul
            if let amountMatch = extractLastMatch(from: line, pattern: RegexPatterns.Amount.flexible) {
                // Yıl kontrolü
                if amountMatch.count == 4 && amountMatch.starts(with: "202") { continue }
                
                let amount = normalizeAmount(amountMatch)
                // Ürün Adı Temizliği
                let name = line.replacingOccurrences(of: RegexPatterns.Amount.flexible, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "TL", with: "")
                    .replacingOccurrences(of: "Adet", with: "")
                
                if !name.isEmpty && amount > 0 {
                    items.append(InvoiceItem(name: name, quantity: 1, unitPrice: amount, total: amount, taxRate: 18))
                }
            }
        }
        return items
    }
    
    private func extractMerchantName(from sellerLines: [String]) -> String {
        for line in sellerLines {
            let upper = line.uppercased()
            if RegexPatterns.Keywords.merchantBlacklist.contains(where: { upper.contains($0) }) { continue }
            if isPhoneNumber(line) { continue }
            
            if RegexPatterns.Keywords.companySuffixes.contains(where: { upper.contains($0) }) {
                return line
            }
        }
        // Fallback (Marka adı)
        for line in sellerLines {
            let upper = line.uppercased()
            if line.count > 3 &&
               !RegexPatterns.Keywords.merchantBlacklist.contains(where: { upper.contains($0) }) &&
               !isPhoneNumber(line) && !upper.contains("NO:") {
                return line
            }
        }
        return ""
    }
    
    private func extractSellerBlock(from lines: [String]) -> [String] {
        for (index, line) in lines.enumerated() {
            if RegexPatterns.Keywords.splitters.contains(where: { line.uppercased().contains($0) }) {
                if index < 1 { return Array(lines.prefix(5)) }
                return Array(lines.prefix(index))
            }
        }
        return Array(lines.prefix(12))
    }
    
    private func extractETTN(from lines: [String], rawText: String) -> String {
        for line in lines {
            if line.uppercased().contains("ETTN") {
                let words = line.components(separatedBy: .whitespaces)
                if let lastWord = words.last, lastWord.count > 20 {
                    return cleanETTN(lastWord)
                }
            }
        }
        if let raw = extractString(from: rawText, pattern: RegexPatterns.ID.ettn) {
            return cleanETTN(raw)
        }
        return ""
    }
    
    private func extractInvoiceNumber(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("IRSALIYE") || line.contains("SIPARIS") || line.contains("SİPARİŞ") || line.contains("REF") { continue }
            
            // 1. Standart Ara
            if let num = extractString(from: line, pattern: RegexPatterns.InvoiceNo.standard) { return num }
            
            // 2. A101 Özel Ara
            if let num = extractString(from: line, pattern: RegexPatterns.InvoiceNo.a101) { return num }
            
            // 3. Kısa Format Ara (Etiketli)
            if line.contains("FATURA NO") || line.contains("FATURA NUMARASI") {
                if let num = extractString(from: line, pattern: RegexPatterns.InvoiceNo.short) { return num }
            }
        }
        // Genel Tarama
        if let num = extractString(from: text, pattern: RegexPatterns.InvoiceNo.standard) { return num }
        return ""
    }
    
    // --- Helper Functions ---
    
    internal func extractLastMatch(from text: String, pattern: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let results = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            if let lastMatch = results.last, let range = Range(lastMatch.range, in: text) {
                return String(text[range])
            }
        } catch {}
        return nil
    }
    
    private func cleanETTN(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "ETTN", with: "").replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: "l", with: "1").replacingOccurrences(of: "O", with: "0")
        return t.lowercased()
    }
    
    private func isPhoneNumber(_ text: String) -> Bool {
        let c = text.replacingOccurrences(of: " ", with: "")
        return c.hasPrefix("+9") || c.hasPrefix("05") || c.contains("TEL")
    }
    
    private func parseDateString(_ s: String) -> Date {
        let f = DateFormatter()
        for fmt in ["dd.MM.yyyy", "dd/MM/yyyy", "dd-MM-yyyy"] { f.dateFormat = fmt; if let d = f.date(from: s) { return d } }
        return Date()
    }
    
    internal func normalizeAmount(_ amountStr: String) -> Double {
        var s = amountStr.replacingOccurrences(of: "[^0-9.,]", with: "", options: .regularExpression)
        if s.contains(".") && s.contains(",") { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        else if s.contains(",") { s = s.replacingOccurrences(of: ",", with: ".") }
        return Double(s) ?? 0.0
    }
    
    internal func extractString(from text: String, pattern: String) -> String? {
        do {
            let r = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let res = r.matches(in: text, range: NSRange(text.startIndex..., in: text))
            if let m = res.first { return String(text[Range(m.range, in: text)!]) }
        } catch {}
        return nil
    }
    
    private func calculateRealConfidence(invoice: Invoice) -> Float {
        var score: Float = 0.0
        var checks: Float = 0.0
        checks += 1; if !invoice.merchantName.isEmpty { score += 1 }
        checks += 1; if !invoice.merchantTaxID.isEmpty { score += 1 }
        checks += 1; if invoice.totalAmount > 0 { score += 1 }
        checks += 1; if invoice.ettn.count > 20 { score += 1 }
        if invoice.totalAmount == 0 { return (score / checks) * 0.5 }
        return score / checks
    }
}
