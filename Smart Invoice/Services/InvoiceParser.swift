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
    
    // Stratejiler
    private let strategies: [InvoiceExtractionStrategy] = [
        VendorStrategy(),         // 1. Satıcı
        InvoiceDetailsStrategy(), // 2. Fatura No, Tarih, ETTN
        ItemsStrategy(),          // 3. Ürünler
        FinancialStrategy()       // 4. Finansal
    ]
    
    func parse(text: String) async -> Invoice {
        // Eski yöntem (String bazlı) - Geriye dönük uyumluluk için
        do {
            return try await parse(blocks: [], rawText: text)
        } catch {
            print("❌ Fallback Parse Hatası: \(error.localizedDescription)")
            return Invoice(userId: "")
        }
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
            
            // 2. Profil Tespiti (Erken Tespit)
            // Stratejiler çalışmadan önce profili bulalım ki onlara ipucu verebilelim
            let textLower = fullText.lowercased()
            var detectedProfile: VendorProfile? = nil
            
            for profile in profiles {
                if profile.applies(to: textLower) {
                    print("✅ Profil Tespit Edildi: \(profile.vendorName)")
                    detectedProfile = profile
                    break
                }
            }
            
            // 3. Stratejileri Çalıştır
            // Context'e profili de ekliyoruz
            let context = ExtractionContext(blocks: blocks, lines: lines, rawText: fullText, profile: detectedProfile)
            
            for strategy in strategies {
                strategy.extract(context: context, invoice: &invoice)
            }
            
            // 4. Profil Kurallarını Uygula (Post-Processing)
            if let profile = detectedProfile {
                profile.applyRules(to: &invoice, rawText: fullText)
            }
            
            // 4. Debug Bölgelerini Hesapla (Faz 3)
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
            if let rect = InvoiceParserHelper.calculateUnionRect(of: sellerLines) {
                invoice.debugRegions.append(OCRRegion(type: .seller, rect: rect))
            }
        } else {
            // Splitter yoksa ilk %20
            let count = max(1, Int(Double(lines.count) * 0.20))
            let sellerLines = Array(lines.prefix(count))
            if let rect = InvoiceParserHelper.calculateUnionRect(of: sellerLines) {
                invoice.debugRegions.append(OCRRegion(type: .seller, rect: rect))
            }
        }
        
        // 2. Tablo Alanı (Mavi)
        if let headerIndex = lines.firstIndex(where: { line in RegexPatterns.Keywords.tableHeaders.contains(where: { line.text.uppercased().contains($0) }) }) {
            let footerIndex = lines.indices.first(where: { index in index > headerIndex && RegexPatterns.Keywords.tableFooters.contains(where: { lines[index].text.uppercased().contains($0) }) }) ?? lines.count
            
            // Header ve Footer dahil edelim ki sınırları görelim
            let endIndex = min(footerIndex + 1, lines.count)
            let tableLines = Array(lines[headerIndex..<endIndex])
            
            if let rect = InvoiceParserHelper.calculateUnionRect(of: tableLines) {
                invoice.debugRegions.append(OCRRegion(type: .table, rect: rect))
            }
        }
        
        // 3. Toplam Tutar (Yeşil)
        // Tutarı içeren bloğu bul
        if invoice.totalAmount > 0 {
            // Tam eşleşme veya normalize edilmiş eşleşme ara
            for block in blocks {
                if let amount = InvoiceParserHelper.findAmountInString(block.text), abs(amount - invoice.totalAmount) < 0.01 {
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
            if InvoiceParserHelper.extractString(from: block.text, pattern: datePattern) != nil {
                // Bulunan tarih bizim extract ettiğimiz tarih mi?
                // Basitçe tarih formatına uyan ilk bloğu işaretleyelim (Genelde doğrudur)
                invoice.debugRegions.append(OCRRegion(type: .date, rect: block.frame))
                break
            }
        }
        
        // 5. KDV (Mor)
        if invoice.taxAmount > 0 {
            for block in blocks {
                if let amount = InvoiceParserHelper.findAmountInString(block.text), abs(amount - invoice.taxAmount) < 0.01 {
                    invoice.debugRegions.append(OCRRegion(type: .tax, rect: block.frame))
                    break
                }
            }
        }
        
        // 6. Ara Toplam (Turuncu)
        if invoice.subTotal > 0 {
            for block in blocks {
                if let amount = InvoiceParserHelper.findAmountInString(block.text), abs(amount - invoice.subTotal) < 0.01 {
                    invoice.debugRegions.append(OCRRegion(type: .subTotal, rect: block.frame))
                    break
                }
            }
        }
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
