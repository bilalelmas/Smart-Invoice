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
        
        // 1. Satırları Oluştur (Gelişmiş Row Clustering)
        let lines = SpatialEngine.clusterRows(blocks)
        let textLines = lines.map { $0.text }
        
        // Eğer blok yoksa (eski yöntem), rawText kullan
        let fullText = rawText ?? textLines.joined(separator: "\n")
        let cleanLines = fullText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // 2. Zoning System: Bölgelere ayır
        let headerLeftBlocks = SpatialEngine.blocks(in: .headerLeft, from: blocks)
        let headerRightBlocks = SpatialEngine.blocks(in: .headerRight, from: blocks)
        let bodyLines = SpatialEngine.lines(in: .body, from: lines)
        let footerLines = SpatialEngine.lines(in: .footer, from: lines)
        
        // 3. Zone-based Veri Çıkarımı
        // Zone A (Header Left): Satıcı Bilgileri
        invoice.merchantName = extractMerchantNameFromZone(blocks: headerLeftBlocks, lines: SpatialEngine.lines(in: .headerLeft, from: lines))
        invoice.merchantTaxID = extractMerchantTaxIDFromZone(blocks: headerLeftBlocks)
        
        // Zone B (Header Right): Fatura No, Tarih, ETTN
        let headerRightLines = SpatialEngine.lines(in: .headerRight, from: lines)
        invoice.invoiceNo = extractInvoiceNumberFromZone(blocks: headerRightBlocks, lines: headerRightLines) ?? extractInvoiceNumber(from: fullText)
        invoice.invoiceDate = extractDateFromZone(blocks: headerRightBlocks, lines: headerRightLines) ?? extractDate(from: cleanLines)
        invoice.ettn = extractETTNFromZone(blocks: headerRightBlocks, lines: headerRightLines) ?? extractETTN(from: cleanLines, rawText: fullText)
        
        // 4. Finansal Veri ve Tablo Analizi
        if !blocks.isEmpty {
            // Zone C (Body): Ürünler/Tablo - Column Detection ile
            invoice.items = extractLineItemsSpatialWithColumns(lines: bodyLines, allBlocks: blocks)
            
            // Zone D (Footer): Finansal Veriler
            // KDV oranını tespit et
            let footerText = footerLines.map { $0.text }.joined(separator: " ")
            let taxRate = extractTaxRate(from: footerText)
            invoice.totalAmount = extractTotalAmountFromZone(lines: footerLines)
            invoice.subTotal = extractSubTotalFromZone(lines: footerLines, totalAmount: invoice.totalAmount, taxRate: taxRate)
            invoice.taxAmount = extractTaxAmountFromZone(lines: footerLines, subTotal: invoice.subTotal, taxRate: taxRate)
        } else {
            invoice.items = extractLineItems(from: cleanLines)
            // KDV oranını tespit et (text-based)
            let taxRate = extractTaxRate(from: fullText)
            invoice.totalAmount = extractTotalAmount(from: fullText)
            invoice.subTotal = extractSubTotal(from: fullText, totalAmount: invoice.totalAmount, taxRate: taxRate)
            invoice.taxAmount = extractTaxAmount(from: fullText, taxRate: taxRate)
        }
        
        // 4.5. Self-Healing: Matematiksel sağlama ile eksik verileri tamamla
        var financialValidation = SpatialEngine.FinancialValidation(
            totalAmount: invoice.totalAmount,
            taxAmount: invoice.taxAmount,
            subTotal: invoice.subTotal
        )
        financialValidation.heal()
        invoice.totalAmount = financialValidation.totalAmount
        invoice.taxAmount = financialValidation.taxAmount
        invoice.subTotal = financialValidation.subTotal
        
        // 4.6. Ek validasyon (Self-healing sonrası)
        validateAndFixAmounts(&invoice)
        
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
    
    // MARK: - 📍 KDV Oranı Tespiti
    
    /// KDV oranını tespit eder (%1, %8, %10, %18, %20) - Spatial ve text-based için ortak
    private func extractTaxRate(from text: String) -> Double {
        return InvoiceParserHelper.extractTaxRate(from: text)
    }
    
    private func extractTaxAmountSpatial(lines: [TextLine], subTotal: Double = 0.0, taxRate: Double = 0.18) -> Double {
        var candidates: [Double] = []
        
        for (index, line) in lines.enumerated().reversed() {
            let upper = line.text.uppercased()
            
            // KDV ile ilgili kelimeleri kontrol et
            // Ama "Ödenecek Tutar" gibi totalAmount kelimelerini atla
            let isTotalAmountLine = RegexPatterns.Keywords.payableAmounts.contains(where: { upper.contains($0) })
            if RegexPatterns.Keywords.taxAmounts.contains(where: { upper.contains($0) }) && !isTotalAmountLine {
                // 1. Aynı satırda ara (En sağdaki değer)
                if let lastBlock = line.blocks.last, let amount = findAmountInString(lastBlock.text) {
                    candidates.append(amount)
                }
                // Tüm satırda ara
                let amounts = findAllAmountsInString(line.text)
                for amt in amounts {
                    if amt > 0 {
                        candidates.append(amt)
                    }
                }
                
                // 2. Bir alt satırda ara (Label üstte, değer altta ise)
                if index + 1 < lines.count {
                    let nextLine = lines[index + 1]
                    let nextAmounts = findAllAmountsInString(nextLine.text)
                    for amt in nextAmounts {
                        if amt > 0 {
                            candidates.append(amt)
                        }
                    }
                }
            }
        }
        
        // İyileştirme: KDV tutarı matrahtan küçük olmalı
        // Ayrıca totalAmount ile karıştırılmamalı
        let maxCandidate = candidates.max() ?? 0.0
        
        if subTotal > 0 {
            let expectedMaxTax = subTotal * taxRate
            // Eğer bulunan KDV matrahtan büyükse, muhtemelen yanlış (totalAmount ile karıştırılmış)
            if maxCandidate > expectedMaxTax * 1.5 { // %50 tolerans
                // Matrahın tespit edilen oranıyla hesapla
                return subTotal * taxRate
            }
            // Eğer bulunan KDV matrahtan büyükse ama çok büyük değilse, filtrele
            if maxCandidate > subTotal {
                // Bu kesinlikle yanlış, matrahın tespit edilen oranıyla hesapla
                return subTotal * taxRate
            }
        }
        
        // Eğer hiçbir aday bulunamadıysa ve subTotal varsa, hesapla
        if candidates.isEmpty && subTotal > 0 {
            return subTotal * taxRate
        }
        
        return maxCandidate
    }
    
    private func extractSubTotalSpatial(lines: [TextLine], totalAmount: Double, taxRate: Double = 0.18) -> Double {
        var candidates: [Double] = []
        var malHizmetCandidates: [Double] = []
        
        for (index, line) in lines.enumerated().reversed() {
            let upper = line.text.uppercased()
            
            // "Mal Hizmet Toplam Tutarı" özel kontrolü
            if RegexPatterns.Keywords.malHizmetKeywords.contains(where: { upper.contains($0) }) {
                let amounts = findAllAmountsInString(line.text)
                for amt in amounts {
                    if amt > 0 {
                        malHizmetCandidates.append(amt)
                    }
                }
                // Bir alt satırda da ara
                if index + 1 < lines.count {
                    let nextLine = lines[index + 1]
                    let nextAmounts = findAllAmountsInString(nextLine.text)
                    for amt in nextAmounts {
                        if amt > 0 {
                            malHizmetCandidates.append(amt)
                        }
                    }
                }
            }
            
            // Ara Toplam / Matrah Kelimeleri (KDV Hariç belirten)
            if RegexPatterns.Keywords.subTotalAmounts.contains(where: { upper.contains($0) }) {
                // 1. Aynı satırda ara (En sağdaki değer)
                if let lastBlock = line.blocks.last, let amount = findAmountInString(lastBlock.text) {
                    candidates.append(amount)
                }
                // Tüm satırda ara
                let amounts = findAllAmountsInString(line.text)
                for amt in amounts {
                    if amt > 0 {
                        candidates.append(amt)
                    }
                }
                
                // 2. Bir alt satırda ara (Label üstte, değer altta ise)
                if index + 1 < lines.count {
                    let nextLine = lines[index + 1]
                    let nextAmounts = findAllAmountsInString(nextLine.text)
                    for amt in nextAmounts {
                        if amt > 0 {
                            candidates.append(amt)
                        }
                    }
                }
            }
        }
        
        // "Mal Hizmet Toplam Tutarı" kontrolü
        // Eğer totalAmount'a yakınsa (fark %5'ten az), vergiler dahil demektir, kullanma
        // Eğer totalAmount'tan küçükse, vergiler hariç olabilir
        if let malHizmetAmount = malHizmetCandidates.max(), malHizmetAmount > 0 {
            if totalAmount > 0 {
                let difference = abs(malHizmetAmount - totalAmount)
                let percentage = (difference / totalAmount) * 100
                // Eğer fark %5'ten fazlaysa, vergiler hariç olabilir
                if percentage > 5.0 {
                    candidates.append(malHizmetAmount)
                }
            } else {
                // TotalAmount yoksa, mal hizmet tutarını kullan
                candidates.append(malHizmetAmount)
            }
        }
        
        // İyileştirme: Eğer hiçbir aday bulunamadıysa ve totalAmount varsa,
        // totalAmount'tan KDV'yi çıkararak matrahı hesapla (varsayılan %18 KDV)
        if candidates.isEmpty && totalAmount > 0 {
            // totalAmount = subTotal + (subTotal * 0.18)
            // totalAmount = subTotal * 1.18
            // subTotal = totalAmount / 1.18
            let estimatedSubTotal = totalAmount / 1.18
            if estimatedSubTotal > 0 {
                candidates.append(estimatedSubTotal)
            }
        }
        
        // Matrah genelde toplam tutardan küçük ama KDV'den büyüktür
        // En büyük adayı alalım, ama totalAmount'tan küçük olmalı
        let maxCandidate = candidates.max() ?? 0.0
        if totalAmount > 0 && maxCandidate > totalAmount {
            // Eğer bulunan değer totalAmount'tan büyükse, muhtemelen yanlış
            // totalAmount'tan KDV'yi çıkararak hesapla
            return totalAmount / 1.18
        }
        return maxCandidate
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
    
    internal func extractTaxAmount(from text: String, taxRate: Double = 0.18) -> Double {
        let lines = text.components(separatedBy: .newlines)
        var candidates: [Double] = []
        
        for line in lines.reversed() {
            let upper = line.uppercased()
            if RegexPatterns.Keywords.taxAmounts.contains(where: { upper.contains($0) }) {
                if let amount = findAmountInString(line) {
                    candidates.append(amount)
                }
                // Tüm tutarları bul (birden fazla olabilir)
                let amounts = findAllAmountsInString(line)
                for amt in amounts {
                    if amt > 0 {
                        candidates.append(amt)
                    }
                }
            }
        }
        
        // En küçük değeri al (çünkü KDV genelde en küçük tutardır)
        // Ama 0'dan büyük olmalı
        let validCandidates = candidates.filter { $0 > 0 }
        let minCandidate = validCandidates.min() ?? 0.0
        
        // Eğer hiçbir aday bulunamadıysa ve subTotal varsa, hesapla
        // Ama burada subTotal yok, bu yüzden sadece bulunan değeri döndür
        return minCandidate
    }
    
    private func extractSubTotal(from text: String, totalAmount: Double, taxRate: Double = 0.18) -> Double {
        let lines = text.components(separatedBy: .newlines)
        var candidates: [Double] = []
        var malHizmetCandidates: [Double] = []
        
        for line in lines.reversed() {
            let upper = line.uppercased()
            
            // "Mal Hizmet Toplam Tutarı" özel kontrolü
            if RegexPatterns.Keywords.malHizmetKeywords.contains(where: { upper.contains($0) }) {
                if let amount = findAmountInString(line) {
                    malHizmetCandidates.append(amount)
                }
            }
            
            // Ara Toplam / Matrah Kelimeleri (KDV Hariç belirten)
            if RegexPatterns.Keywords.subTotalAmounts.contains(where: { upper.contains($0) }) {
                if let amount = findAmountInString(line) {
                    candidates.append(amount)
                }
            }
        }
        
        // "Mal Hizmet Toplam Tutarı" kontrolü
        if let malHizmetAmount = malHizmetCandidates.max(), malHizmetAmount > 0 {
            if totalAmount > 0 {
                let difference = abs(malHizmetAmount - totalAmount)
                let percentage = (difference / totalAmount) * 100
                // Eğer fark %5'ten fazlaysa, vergiler hariç olabilir
                if percentage > 5.0 {
                    candidates.append(malHizmetAmount)
                }
            } else {
                candidates.append(malHizmetAmount)
            }
        }
        
        // İyileştirme: Eğer hiçbir aday bulunamadıysa ve totalAmount varsa,
        // totalAmount'tan KDV'yi çıkararak matrahı hesapla
        if candidates.isEmpty && totalAmount > 0 {
            // totalAmount = subTotal + (subTotal * taxRate)
            // totalAmount = subTotal * (1 + taxRate)
            // subTotal = totalAmount / (1 + taxRate)
            let estimatedSubTotal = totalAmount / (1 + taxRate)
            if estimatedSubTotal > 0 {
                candidates.append(estimatedSubTotal)
            }
        }
        
        // Matrah genelde toplam tutardan küçük olmalı
        let maxCandidate = candidates.max() ?? 0.0
        if totalAmount > 0 && maxCandidate > totalAmount {
            // Eğer bulunan değer totalAmount'tan büyükse, muhtemelen yanlış
            // totalAmount'tan KDV'yi çıkararak hesapla
            return totalAmount / (1 + taxRate)
        }
        return maxCandidate
    }
    
    /// Tutarları doğrula ve düzelt
    /// - KDV tutarı matrahtan küçük olmalı (çünkü %20'ye kadar bir oran var)
    /// - Matrah + KDV ≈ Toplam olmalı
    private func validateAndFixAmounts(_ invoice: inout Invoice) {
        // 1. KDV tutarının matrahtan küçük olduğunu kontrol et
        if invoice.subTotal > 0 && invoice.taxAmount > 0 {
            // KDV tutarı matrahtan büyükse, muhtemelen yanlış (totalAmount ile karıştırılmış)
            // KDV genelde matrahın %1-20'si arasındadır
            let maxTaxRate = 0.20 // %20
            let expectedMaxTax = invoice.subTotal * maxTaxRate
            
            if invoice.taxAmount > expectedMaxTax {
                // KDV tutarı çok büyük, muhtemelen yanlış (totalAmount ile karıştırılmış)
                // Matrah ve KDV'yi yeniden hesapla
                if invoice.totalAmount > 0 {
                    // totalAmount = subTotal + taxAmount
                    // taxAmount = totalAmount - subTotal
                    let calculatedTax = invoice.totalAmount - invoice.subTotal
                    if calculatedTax > 0 && calculatedTax <= expectedMaxTax {
                        invoice.taxAmount = calculatedTax
                    } else {
                        // Hala mantıksızsa, KDV'yi matrahtan hesapla (varsayılan %18)
                        invoice.taxAmount = invoice.subTotal * 0.18
                    }
                } else {
                    // TotalAmount yoksa, KDV'yi matrahtan hesapla
                    invoice.taxAmount = invoice.subTotal * 0.18
                }
            }
        }
        
        // 2. Matrah + KDV ≈ Toplam kontrolü
        if invoice.subTotal > 0 && invoice.taxAmount > 0 && invoice.totalAmount > 0 {
            let calculatedTotal = invoice.subTotal + invoice.taxAmount
            let difference = abs(calculatedTotal - invoice.totalAmount)
            let percentage = (difference / invoice.totalAmount) * 100
            
            // Eğer fark %2'den fazlaysa, matrahı yeniden hesapla
            if percentage > 2.0 {
                // totalAmount = subTotal + taxAmount
                // subTotal = totalAmount - taxAmount
                let calculatedSubTotal = invoice.totalAmount - invoice.taxAmount
                if calculatedSubTotal > 0 {
                    invoice.subTotal = calculatedSubTotal
                }
            }
        }
        
        // 3. Eğer matrah yoksa ama toplam ve KDV varsa, matrahı hesapla
        if invoice.subTotal == 0 && invoice.totalAmount > 0 && invoice.taxAmount > 0 {
            invoice.subTotal = invoice.totalAmount - invoice.taxAmount
        }
        
        // 4. Eğer KDV yoksa ama toplam ve matrah varsa, KDV'yi hesapla
        if invoice.taxAmount == 0 && invoice.totalAmount > 0 && invoice.subTotal > 0 {
            invoice.taxAmount = invoice.totalAmount - invoice.subTotal
        }
        
        // 5. İyileştirme: Eğer matrah 0 ise ama toplam varsa, matrahı hesapla
        if invoice.subTotal == 0 && invoice.totalAmount > 0 {
            // Varsayılan %18 KDV ile hesapla
            // totalAmount = subTotal * 1.18
            // subTotal = totalAmount / 1.18
            invoice.subTotal = invoice.totalAmount / 1.18
            if invoice.taxAmount == 0 {
                invoice.taxAmount = invoice.totalAmount - invoice.subTotal
            }
        }
        
        // 6. İyileştirme: Eğer KDV matrahtan büyükse (totalAmount ile karıştırılmış), düzelt
        if invoice.subTotal > 0 && invoice.taxAmount > invoice.subTotal {
            // Bu kesinlikle yanlış, KDV'yi matrahtan hesapla
            invoice.taxAmount = invoice.subTotal * 0.18
            // TotalAmount'u da güncelle
            if invoice.totalAmount == 0 {
                invoice.totalAmount = invoice.subTotal + invoice.taxAmount
            }
        }
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
        // 1. ETTN etiketli satırlarda ara
        for line in lines {
            let upper = line.uppercased()
            if upper.contains("ETTN") {
                // ETTN kelimesinden sonraki kısmı al
                if let ettnIndex = upper.range(of: "ETTN") {
                    let afterETTN = String(line[ettnIndex.upperBound...])
                    let words = afterETTN.components(separatedBy: .whitespacesAndNewlines)
                    for word in words {
                        let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: ":", with: "")
                            .replacingOccurrences(of: "-", with: "")
                        // UUID formatı kontrolü (32 hex karakter)
                        if cleaned.count >= 32 {
                            // UUID formatına çevir
                            let ettn = formatETTN(cleaned)
                            if !ettn.isEmpty {
                                return ettn
                            }
                        }
                    }
                }
            }
        }
        
        // 2. Regex ile genel arama (daha esnek pattern)
        // ETTN formatı: 8-4-4-4-12 hex karakter
        let flexibleETTNPattern = "[a-fA-F0-9]{8}[- ]?[a-fA-F0-9]{4}[- ]?[a-fA-F0-9]{4}[- ]?[a-fA-F0-9]{4}[- ]?[a-fA-F0-9]{12}"
        if let raw = extractString(from: rawText, pattern: flexibleETTNPattern) {
            return cleanETTN(raw)
        }
        
        // 3. Standart UUID pattern
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
    
    // MARK: - Helper Function Delegates (InvoiceParserHelper'a yönlendir)
    
    internal func extractLastMatch(from text: String, pattern: String) -> String? {
        return InvoiceParserHelper.extractLastMatch(from: text, pattern: pattern)
    }
    
    private func cleanETTN(_ text: String) -> String {
        return InvoiceParserHelper.cleanETTN(text)
    }
    
    private func formatETTN(_ text: String) -> String {
        return InvoiceParserHelper.formatETTN(text)
    }
    
    private func isPhoneNumber(_ text: String) -> Bool {
        return InvoiceParserHelper.isPhoneNumber(text)
    }
    
    private func parseDateString(_ s: String) -> Date {
        return InvoiceParserHelper.parseDateString(s)
    }
    
    internal func normalizeAmount(_ amountStr: String) -> Double {
        return InvoiceParserHelper.normalizeAmount(amountStr)
    }
    
    internal func extractString(from text: String, pattern: String) -> String? {
        return InvoiceParserHelper.extractString(from: text, pattern: pattern)
    }
    
    private func findAmountInString(_ text: String) -> Double? {
        return InvoiceParserHelper.findAmountInString(text)
    }
    
    private func findAllAmountsInString(_ text: String) -> [Double] {
        return InvoiceParserHelper.findAllAmountsInString(text)
    }
    
    private func extractETTNFromText(_ text: String) -> String {
        return InvoiceParserHelper.extractETTNFromText(text)
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
    
    // MARK: - Zone-based Extraction Methods
    
    /// Zone A (Header Left): Satıcı adını çıkarır
    private func extractMerchantNameFromZone(blocks: [TextBlock], lines: [TextLine]) -> String {
        // Önce satırlarda ara (daha güvenilir)
        for line in lines {
            let upper = line.text.uppercased()
            if RegexPatterns.Keywords.merchantBlacklist.contains(where: { upper.contains($0) }) { continue }
            if isPhoneNumber(line.text) { continue }
            
            if RegexPatterns.Keywords.companySuffixes.contains(where: { upper.contains($0) }) {
                return line.text
            }
        }
        
        // Fallback: Bloklarda ara
        for block in blocks.sorted(by: { $0.y < $1.y }) {
            let upper = block.text.uppercased()
            if RegexPatterns.Keywords.merchantBlacklist.contains(where: { upper.contains($0) }) { continue }
            if isPhoneNumber(block.text) { continue }
            
            if RegexPatterns.Keywords.companySuffixes.contains(where: { upper.contains($0) }) {
                return block.text
            }
        }
        
        return ""
    }
    
    /// Zone A (Header Left): Satıcı vergi numarasını çıkarır
    private func extractMerchantTaxIDFromZone(blocks: [TextBlock]) -> String {
        for block in blocks {
            let upper = block.text.uppercased()
            
            // VKN etiketli satırlarda ara
            if upper.contains("VKN") || upper.contains("VERGI") {
                if let id = extractString(from: block.text, pattern: RegexPatterns.ID.vkn) {
                    return id
                }
            }
            
            // Etiketsiz 10 hane ara (ama telefon numarası değil)
            if !isPhoneNumber(block.text) {
                if let id = extractString(from: block.text, pattern: RegexPatterns.ID.vkn) {
                    return id
                }
            }
        }
        
        return ""
    }
    
    /// Zone B (Header Right): Fatura numarasını çıkarır
    private func extractInvoiceNumberFromZone(blocks: [TextBlock], lines: [TextLine]) -> String? {
        // Önce satırlarda ara
        for line in lines {
            let upper = line.text.uppercased()
            if upper.contains("FATURA NO") || upper.contains("FATURA NUMARASI") {
                // Standart format
                if let num = extractString(from: line.text, pattern: RegexPatterns.InvoiceNo.standard) {
                    return num
                }
                // A101 format
                if let num = extractString(from: line.text, pattern: RegexPatterns.InvoiceNo.a101) {
                    return num
                }
            }
            
            // Etiketsiz arama
            if let num = extractString(from: line.text, pattern: RegexPatterns.InvoiceNo.standard) {
                return num
            }
        }
        
        // Fallback: Bloklarda ara
        for block in blocks {
            if let num = extractString(from: block.text, pattern: RegexPatterns.InvoiceNo.standard) {
                return num
            }
        }
        
        return nil
    }
    
    /// Zone B (Header Right): Tarihi çıkarır
    private func extractDateFromZone(blocks: [TextBlock], lines: [TextLine]) -> Date? {
        let datePattern = RegexPatterns.DateFormat.standard
        
        // Önce etiketli satırlarda ara
        for line in lines {
            let upper = line.text.uppercased()
            if RegexPatterns.Keywords.dateTargets.contains(where: { upper.contains($0) }) &&
               !RegexPatterns.Keywords.dateBlacklist.contains(where: { upper.contains($0) }) {
                for block in line.blocks {
                    if let dateStr = extractString(from: block.text, pattern: datePattern) {
                        return parseDateString(dateStr)
                    }
                }
                if let dateStr = extractString(from: line.text, pattern: datePattern) {
                    return parseDateString(dateStr)
                }
            }
        }
        
        // Genel arama (ilk 10 satır)
        for line in lines.prefix(10) {
            let upper = line.text.uppercased()
            if RegexPatterns.Keywords.dateBlacklist.contains(where: { upper.contains($0) }) { continue }
            
            for block in line.blocks {
                if let dateStr = extractString(from: block.text, pattern: datePattern) {
                    return parseDateString(dateStr)
                }
            }
        }
        
        return nil
    }
    
    /// Zone B (Header Right): ETTN'i çıkarır
    private func extractETTNFromZone(blocks: [TextBlock], lines: [TextLine]) -> String? {
        // Önce etiketli satırlarda ara
        for line in lines {
            let upper = line.text.uppercased()
            if upper.contains("ETTN") {
                if let ettnIndex = upper.range(of: "ETTN") {
                    let afterETTN = String(line.text[ettnIndex.upperBound...])
                    let ettn = extractETTNFromText(afterETTN)
                    if !ettn.isEmpty {
                        return ettn
                    }
                }
            }
        }
        
        // Genel arama
        let allText = blocks.map { $0.text }.joined(separator: " ")
        let ettn = extractETTNFromText(allText)
        return ettn.isEmpty ? nil : ettn
    }
    
    /// Zone D (Footer): Toplam tutarı çıkarır
    private func extractTotalAmountFromZone(lines: [TextLine]) -> Double {
        var candidates: [Double] = []
        
        // Alttan yukarı doğru tara (genelde toplam en alttadır)
        for line in lines.reversed() {
            let upper = line.text.uppercased()
            
            // Kara liste kontrolü
            if RegexPatterns.Keywords.amountBlacklist.contains(where: { upper.contains($0) }) { continue }
            // KDV kelimelerini atla (totalAmount ile karıştırmamak için)
            if RegexPatterns.Keywords.taxAmounts.contains(where: { upper.contains($0) }) && 
               !RegexPatterns.Keywords.payableAmounts.contains(where: { upper.contains($0) }) {
                continue
            }
            
            // Hedef kelime kontrolü (Ödenecek Tutar)
            if RegexPatterns.Keywords.payableAmounts.contains(where: { upper.contains($0) }) {
                // En sağdaki blok fiyat adayıdır
                if let lastBlock = line.blocks.last, let amount = findAmountInString(lastBlock.text) {
                    candidates.append(amount)
                }
                // Tüm satırda ara
                let amounts = findAllAmountsInString(line.text)
                for amt in amounts {
                    if amt > 0 {
                        candidates.append(amt)
                    }
                }
            }
        }
        
        return candidates.max() ?? 0.0
    }
    
    /// Zone D (Footer): Ara toplamı çıkarır
    private func extractSubTotalFromZone(lines: [TextLine], totalAmount: Double, taxRate: Double) -> Double {
        var candidates: [Double] = []
        
        for line in lines.reversed() {
            let upper = line.text.uppercased()
            
            // Ara Toplam / Matrah Kelimeleri
            if RegexPatterns.Keywords.subTotalAmounts.contains(where: { upper.contains($0) }) {
                if let lastBlock = line.blocks.last, let amount = findAmountInString(lastBlock.text) {
                    candidates.append(amount)
                }
                let amounts = findAllAmountsInString(line.text)
                for amt in amounts {
                    if amt > 0 {
                        candidates.append(amt)
                    }
                }
            }
        }
        
        // Eğer hiçbir aday bulunamadıysa, totalAmount'tan hesapla
        if candidates.isEmpty && totalAmount > 0 {
            return totalAmount / (1 + taxRate)
        }
        
        let maxCandidate = candidates.max() ?? 0.0
        if totalAmount > 0 && maxCandidate > totalAmount {
            return totalAmount / (1 + taxRate)
        }
        
        return maxCandidate
    }
    
    /// Zone D (Footer): KDV tutarını çıkarır
    private func extractTaxAmountFromZone(lines: [TextLine], subTotal: Double, taxRate: Double) -> Double {
        var candidates: [Double] = []
        
        for line in lines.reversed() {
            let upper = line.text.uppercased()
            
            // KDV ile ilgili kelimeleri kontrol et
            // Ama "Ödenecek Tutar" gibi totalAmount kelimelerini atla
            let isTotalAmountLine = RegexPatterns.Keywords.payableAmounts.contains(where: { upper.contains($0) })
            if RegexPatterns.Keywords.taxAmounts.contains(where: { upper.contains($0) }) && !isTotalAmountLine {
                if let lastBlock = line.blocks.last, let amount = findAmountInString(lastBlock.text) {
                    candidates.append(amount)
                }
                let amounts = findAllAmountsInString(line.text)
                for amt in amounts {
                    if amt > 0 {
                        candidates.append(amt)
                    }
                }
            }
        }
        
        let maxCandidate = candidates.max() ?? 0.0
        
        // Validasyon: KDV matrahtan küçük olmalı
        if subTotal > 0 {
            let expectedMaxTax = subTotal * taxRate * 1.5 // %50 tolerans
            if maxCandidate > expectedMaxTax {
                return subTotal * taxRate
            }
            if maxCandidate > subTotal {
                return subTotal * taxRate
            }
        }
        
        // Eğer hiçbir aday bulunamadıysa, matrahtan hesapla
        if candidates.isEmpty && subTotal > 0 {
            return subTotal * taxRate
        }
        
        return maxCandidate
    }
    
    /// Zone C (Body): Column Detection ile ürünleri çıkarır
    private func extractLineItemsSpatialWithColumns(lines: [TextLine], allBlocks: [TextBlock]) -> [InvoiceItem] {
        var items: [InvoiceItem] = []
        
        // 1. Sütunları tespit et
        let columns = SpatialEngine.detectColumns(in: lines)
        print("📍 Tespit edilen sütun sayısı: \(columns.count)")
        
        // 2. Tablo başlığını bul
        guard let headerIndex = lines.firstIndex(where: { line in
            RegexPatterns.Keywords.tableHeaders.contains(where: { line.text.uppercased().contains($0) })
        }) else {
            // Tablo başlığı yoksa, sütun tespiti ile devam et
            return extractItemsWithColumnDetection(lines: lines, columns: columns)
        }
        
        // 3. Tablo bitişini bul
        let footerIndex = lines.indices.first(where: { index in
            index > headerIndex && RegexPatterns.Keywords.tableFooters.contains(where: { lines[index].text.uppercased().contains($0) })
        }) ?? lines.count
        
        // 4. Satırları işle
        for i in (headerIndex + 1)..<footerIndex {
            let line = lines[i]
            if line.blocks.isEmpty { continue }
            
            // Sütun tespiti varsa, sütunlara göre parse et
            if !columns.isEmpty {
                if let item = extractItemFromLineWithColumns(line: line, columns: columns) {
                    items.append(item)
                }
            } else {
                // Fallback: Eski yöntem (en sağdaki blok fiyat)
                if let lastBlock = line.blocks.last, let amount = findAmountInString(lastBlock.text) {
                    let nameBlocks = line.blocks.dropLast()
                    let name = nameBlocks.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        items.append(InvoiceItem(name: name, quantity: 1, unitPrice: amount, total: amount, taxRate: 18))
                    }
                }
            }
        }
        
        return items
    }
    
    /// Sütun tespiti ile ürün çıkarımı (tablo başlığı yoksa)
    private func extractItemsWithColumnDetection(lines: [TextLine], columns: [CGFloat]) -> [InvoiceItem] {
        var items: [InvoiceItem] = []
        
        for line in lines {
            if line.blocks.count < 2 { continue } // En az 2 blok olmalı
            
            // En sağdaki sütunda fiyat ara
            if let lastBlock = line.blocks.last,
               SpatialEngine.columnIndex(for: lastBlock, columns: columns) == columns.count - 1 {
                if let amount = findAmountInString(lastBlock.text) {
                    let nameBlocks = line.blocks.dropLast()
                    let name = nameBlocks.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        items.append(InvoiceItem(name: name, quantity: 1, unitPrice: amount, total: amount, taxRate: 18))
                    }
                }
            }
        }
        
        return items
    }
    
    /// Bir satırdan sütun tespiti ile ürün çıkarır
    private func extractItemFromLineWithColumns(line: TextLine, columns: [CGFloat]) -> InvoiceItem? {
        guard line.blocks.count >= 2 else { return nil }
        
        // En sağdaki sütunda fiyat ara
        if let lastBlock = line.blocks.last,
           let columnIndex = SpatialEngine.columnIndex(for: lastBlock, columns: columns),
           columnIndex == columns.count - 1 {
            if let amount = findAmountInString(lastBlock.text) {
                let nameBlocks = line.blocks.dropLast()
                let name = nameBlocks.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    return InvoiceItem(name: name, quantity: 1, unitPrice: amount, total: amount, taxRate: 18)
                }
            }
        }
        
        return nil
    }
}

