import Foundation
import CoreGraphics

/// InvoiceParser için özel hata tipleri
enum InvoiceParserError: LocalizedError {
    case emptyInput
    case invalidData(String)
    
    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Girdi verisi boş"
        case .invalidData(let message):
            return "Geçersiz veri: \(message)"
        }
    }
}

class InvoiceParser: InvoiceParserProtocol {
    
    static let shared = InvoiceParser()
    private init() {}
    
    // Thread safety için serial queue
    private let parseQueue = DispatchQueue(label: "com.smartinvoice.parser", qos: .userInitiated)
    
    private let profiles: [VendorProfile] = [
        TrendyolProfile(),
        A101Profile(),
        FLOProfile()
    ]
    
    func parse(text: String) async -> Invoice {
        // Eski yöntem (String bazlı) - Geriye dönük uyumluluk için
        return (try? await parse(blocks: [], rawText: text)) ?? Invoice(userId: "")
    }
    
    /// Konumsal Analiz Motoru (Spatial Analysis Engine)
    /// Blokları koordinatlarına göre satırlara ayırır ve işler.
    /// Thread-safe: Serial queue kullanarak eşzamanlı çağrıları sıraya koyar.
    /// - Throws: InvoiceParserError
    func parse(blocks: [TextBlock], rawText: String? = nil) async throws -> Invoice {
        // Thread-safe: Parse işlemini serial queue'da çalıştır
        return try parseQueue.sync {
        // Boş input kontrolü
        if blocks.isEmpty && (rawText == nil || rawText?.isEmpty == true) {
            print("❌ InvoiceParser: Boş input - blocks: \(blocks.count), rawText: \(rawText?.count ?? 0) karakter")
            throw InvoiceParserError.emptyInput
        }
        
        print("✅ InvoiceParser: Parse başlıyor - blocks: \(blocks.count), rawText: \(rawText?.count ?? 0) karakter")
        
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
        // Tarih çıkarımı: Önce bloklardan spatial bilgi kullan, yoksa cleanLines'dan
        if !blocks.isEmpty {
            invoice.invoiceDate = extractDateSpatial(blocks: blocks, lines: lines) ?? extractDate(from: cleanLines)
        } else {
            invoice.invoiceDate = extractDate(from: cleanLines)
        }
        invoice.ettn = extractETTN(from: cleanLines, rawText: fullText)
        invoice.invoiceNo = extractInvoiceNumber(from: fullText)
        
        // 4. Finansal Veri ve Tablo Analizi
        if !blocks.isEmpty {
            invoice.items = extractLineItemsSpatial(lines: lines)
            invoice.totalAmount = extractTotalAmountSpatial(lines: lines)
            invoice.taxAmount = extractTaxAmountSpatial(lines: lines)
            invoice.subTotal = extractSubTotalSpatial(lines: lines)
        } else {
            invoice.items = extractLineItems(from: cleanLines)
            invoice.totalAmount = extractTotalAmount(from: fullText)
            invoice.taxAmount = extractTaxAmount(from: fullText)
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
        
        // 5. KDV (Mor)
        if invoice.taxAmount > 0 {
            for block in blocks {
                if let amount = findAmountInString(block.text), abs(amount - invoice.taxAmount) < 0.01 {
                    invoice.debugRegions.append(OCRRegion(type: .tax, rect: block.frame))
                    break
                }
            }
        }
        
        // 6. Ara Toplam (Turuncu)
        if invoice.subTotal > 0 {
            for block in blocks {
                if let amount = findAmountInString(block.text), abs(amount - invoice.subTotal) < 0.01 {
                    invoice.debugRegions.append(OCRRegion(type: .subTotal, rect: block.frame))
                    break
                }
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
    /// Artık koordinatlar UIKit sisteminde (sol üst köşe), Y değeri yukarıdan aşağıya artar.
    private func groupBlocksIntoLines(_ blocks: [TextBlock]) -> [TextLine] {
        guard !blocks.isEmpty else { return [] }
        
        // Blokları Y konumuna göre sırala (yukarıdan aşağıya: küçükten büyüğe)
        // UIKit koordinat sisteminde Y=0 en üst, Y=1 en alttır
        let sortedBlocks = blocks.sorted { $0.y < $1.y }
        
        var lines: [TextLine] = []
        var currentLineBlocks: [TextBlock] = []
        
        // Dinamik tolerans hesapla (blokların ortalama yüksekliğine göre)
        let avgHeight = blocks.map { $0.height }.reduce(0, +) / CGFloat(blocks.count)
        let tolerance = max(0.01, avgHeight * 0.3) // Yüksekliğin %30'u veya minimum 0.01
        
        for block in sortedBlocks {
            if let lastBlock = currentLineBlocks.last {
                // Y farkı tolerans içindeyse aynı satırdadır
                if abs(block.midY - lastBlock.midY) < tolerance {
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
    
    // MARK: - 📍 Konumsal Tutar Analizi
    
    private func extractTotalAmountSpatial(lines: [TextLine]) -> Double {
        // Alttan yukarı doğru tara (Genelde toplam en alttadır)
        for (index, line) in lines.enumerated().reversed() {
            let upper = line.text.uppercased()
            
            // Kara liste kontrolü
            if RegexPatterns.Keywords.amountBlacklist.contains(where: { upper.contains($0) }) { continue }
            
            // Hedef kelime kontrolü (Ödenecek Tutar)
            if RegexPatterns.Keywords.payableAmounts.contains(where: { upper.contains($0) }) {
                // 1. Aynı satırda ara (En sağdaki değer)
                if let lastBlock = line.blocks.last, let amount = findAmountInString(lastBlock.text) {
                    return amount
                }
                // Blok bazlı bulamazsa tüm satırda ara
                if let amount = findAmountInString(line.text) {
                    return amount
                }
                
                // 2. Bir alt satırda ara (Label üstte, değer altta ise)
                if index + 1 < lines.count {
                    let nextLine = lines[index + 1]
                    // Alt satırda sayı varsa ve çok uzak değilse
                    if let amount = findAmountInString(nextLine.text) {
                        return amount
                    }
                }
            }
        }
        return 0.0
    }
    
    private func extractTaxAmountSpatial(lines: [TextLine]) -> Double {
        for line in lines.reversed() {
            let upper = line.text.uppercased()
            if RegexPatterns.Keywords.taxAmounts.contains(where: { upper.contains($0) }) {
                // En sağdaki değeri al
                if let lastBlock = line.blocks.last, let amount = findAmountInString(lastBlock.text) {
                    return amount
                }
                if let amount = findAmountInString(line.text) {
                    return amount
                }
            }
        }
        return 0.0
    }
    
    private func extractSubTotalSpatial(lines: [TextLine]) -> Double {
        for line in lines.reversed() {
            let upper = line.text.uppercased()
            // Ara Toplam / Matrah Kelimeleri
            if RegexPatterns.Keywords.subTotalAmounts.contains(where: { upper.contains($0) }) {
                 if let amount = findAmountInString(line.text) { return amount }
            }
        }
        return 0.0
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
            if RegexPatterns.Keywords.payableAmounts.contains(where: { upper.contains($0) }) {
                if let amount = findAmountInString(line) {
                    candidates.append(amount)
                }
            }
        }
        
        // "Ödenecek" alt satır kontrolü
        for (index, line) in lines.enumerated().reversed() {
            if RegexPatterns.Keywords.payableAmounts.contains(where: { line.uppercased().contains($0) }) {
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
    
    /// Konumsal analiz ile tarih çıkarımı (bloklardan)
    private func extractDateSpatial(blocks: [TextBlock], lines: [TextLine]) -> Date? {
        let datePattern = RegexPatterns.DateFormat.standard
        
        // 1. Önce etiketli satırlarda ara (FATURA TARİHİ, DÜZENLEME TARİHİ vb.)
        for line in lines {
            let upper = line.text.uppercased()
            if RegexPatterns.Keywords.dateTargets.contains(where: { upper.contains($0) }) &&
               !RegexPatterns.Keywords.dateBlacklist.contains(where: { upper.contains($0) }) {
                // Aynı satırdaki bloklarda tarih ara
                for block in line.blocks {
                    if let dateStr = extractString(from: block.text, pattern: datePattern) {
                        return parseDateString(dateStr)
                    }
                }
                // Satır metninde ara
                if let dateStr = extractString(from: line.text, pattern: datePattern) {
                    return parseDateString(dateStr)
                }
            }
        }
        
        // 2. Üst bölgede (ilk 20 satır) genel arama
        let limit = min(lines.count, 20)
        for i in 0..<limit {
            let line = lines[i]
            let upper = line.text.uppercased()
            
            // Kara listede varsa atla
            if RegexPatterns.Keywords.dateBlacklist.contains(where: { upper.contains($0) }) { continue }
            
            // Satırdaki bloklarda ara
            for block in line.blocks {
                if let dateStr = extractString(from: block.text, pattern: datePattern) {
                    return parseDateString(dateStr)
                }
            }
            
            // Satır metninde ara
            if let dateStr = extractString(from: line.text, pattern: datePattern) {
                return parseDateString(dateStr)
            }
        }
        
        return nil
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
        guard let regex = RegexPatterns.getRegex(pattern: pattern) else { return nil }
        let results = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        if let lastMatch = results.last, let range = Range(lastMatch.range, in: text) {
            return String(text[range])
        }
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
        f.locale = Locale(identifier: "tr_TR") // Türkçe locale
        f.timeZone = TimeZone.current
        
        // Tarih formatlarını dene
        let formats = ["dd.MM.yyyy", "dd/MM/yyyy", "dd-MM-yyyy", "d.M.yyyy", "d/M/yyyy", "d-M-yyyy"]
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: s) {
                return d
            }
        }
        
        // Eğer hiçbiri çalışmazsa bugünün tarihini döndür (fallback)
        return Date()
    }
    
    internal func normalizeAmount(_ amountStr: String) -> Double {
        var s = amountStr.replacingOccurrences(of: "[^0-9.,]", with: "", options: .regularExpression)
        if s.contains(".") && s.contains(",") { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        else if s.contains(",") { s = s.replacingOccurrences(of: ",", with: ".") }
        return Double(s) ?? 0.0
    }
    
    internal func extractString(from text: String, pattern: String) -> String? {
        guard let regex = RegexPatterns.getRegex(pattern: pattern, options: .caseInsensitive) else { return nil }
        let res = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        if let m = res.first, let range = Range(m.range, in: text) {
            return String(text[range])
        }
        return nil
    }
    
    private func calculateRealConfidence(invoice: Invoice) -> Float {
        var score: Float = 0.0
        var totalWeight: Float = 0.0
        
        // 1. Temel alanlar kontrolü (Ağırlık: %40)
        let basicFieldsWeight: Float = 0.4
        totalWeight += basicFieldsWeight
        var basicScore: Float = 0.0
        var basicChecks: Float = 0.0
        
        basicChecks += 1
        if !invoice.merchantName.isEmpty { basicScore += 1 }
        
        basicChecks += 1
        if !invoice.merchantTaxID.isEmpty { basicScore += 1 }
        
        basicChecks += 1
        if invoice.totalAmount > 0 { basicScore += 1 }
        
        basicChecks += 1
        if invoice.ettn.count > 20 { basicScore += 1 }
        
        let basicConfidence = basicChecks > 0 ? (basicScore / basicChecks) : 0.0
        score += basicConfidence * basicFieldsWeight
        
        // 2. Finansal veriler kontrolü (Ağırlık: %30)
        let financialWeight: Float = 0.3
        totalWeight += financialWeight
        var financialScore: Float = 0.0
        
        if invoice.totalAmount > 0 {
            financialScore += 1.0
            // Ara toplam ve KDV tutarlılık kontrolü
            if invoice.subTotal > 0 && invoice.taxAmount > 0 {
                let calculatedTotal = invoice.subTotal + invoice.taxAmount
                let difference = abs(invoice.totalAmount - calculatedTotal)
                // %1 tolerans içindeyse ekstra puan
                if difference < invoice.totalAmount * 0.01 {
                    financialScore += 0.5
                }
            }
        }
        
        score += min(financialScore / 1.5, 1.0) * financialWeight
        
        // 3. Veri kalitesi kontrolü (Ağırlık: %20)
        let qualityWeight: Float = 0.2
        totalWeight += qualityWeight
        var qualityScore: Float = 0.0
        
        // Fatura numarası format kontrolü
        if !invoice.invoiceNo.isEmpty {
            qualityScore += 0.5
            // E-Arşiv formatı kontrolü (3 harf + yıl + 9 rakam)
            if invoice.invoiceNo.count >= 14 {
                qualityScore += 0.5
            }
        }
        
        // Tarih geçerliliği kontrolü
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDate(invoice.invoiceDate, inSameDayAs: now) || invoice.invoiceDate < now {
            qualityScore += 0.5
        }
        
        score += min(qualityScore / 1.5, 1.0) * qualityWeight
        
        // 4. Ürün kalemleri kontrolü (Ağırlık: %10)
        let itemsWeight: Float = 0.1
        totalWeight += itemsWeight
        let itemsScore: Float = invoice.items.isEmpty ? 0.0 : 1.0
        score += itemsScore * itemsWeight
        
        // Toplam tutar 0 ise confidence'ı düşür
        if invoice.totalAmount == 0 {
            return score * 0.5
        }
        
        return min(score / totalWeight, 1.0)
    }
}
