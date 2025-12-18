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
            // 0. Input doğrulama
            try validateInput(blocks: blocks, rawText: rawText)
            
            print("✅ InvoiceParser: Parse başlıyor - blocks: \(blocks.count), rawText: \(rawText?.count ?? 0) karakter")
            
            // 1. Girdi Hazırlama: bloklardan satırları üret, fullText oluştur
            let (preparedBlocks, lines, fullText) = prepareInput(blocks: blocks, rawText: rawText)
            
            var invoice = Invoice(userId: "")
            
            // 2. Profil Tespiti: VendorProfile.applyRules çalışmadan önce tek kez çağrılır; ilk eşleşen profil seçilir.
            let profile = detectProfile(fromFullText: fullText)
            
            // 3. Stratejileri Çalıştır: Satıcı, detaylar, ürünler, finansal alanlar
            let context = ExtractionContext(blocks: preparedBlocks, lines: lines, rawText: fullText, profile: profile)
            runStrategies(context: context, invoice: &invoice)
            
            // 4. Vendor Post-Processing: Profil spesifik kurallar
            applyVendorRules(profile: profile, invoice: &invoice, context: context)
            
            // 5. Debug Region Üretimi: Görsel açıklama bölgeleri
            if !preparedBlocks.isEmpty {
                buildDebugRegions(invoice: &invoice, blocks: preparedBlocks, lines: lines)
            }
            
            // 6. Confidence Hesabı: Alan bazlı skorların ağırlıklı birleşimi
            invoice.confidenceScore = computeConfidence(for: invoice)
            return invoice
        }
    }
    
    // MARK: - Parsing Pipeline Helpers
    
    /// 0. Input doğrulama: Hem bloklar hem rawText boşsa parse işlemi başlatılmaz.
    private func validateInput(blocks: [TextBlock], rawText: String?) throws {
        if blocks.isEmpty && (rawText == nil || rawText?.isEmpty == true) {
            print("❌ InvoiceParser: Boş input - blocks: \(blocks.count), rawText: \(rawText?.count ?? 0) karakter")
            throw InvoiceParserError.emptyInput
        }
    }
    
    /// 1. Girdi Hazırlama:
    /// - Bloklardan satır kümelerini (clusterRows) üretir.
    /// - Eğer rawText yoksa satırların text'lerinden fullText üretir.
    private func prepareInput(blocks: [TextBlock], rawText: String?) -> (blocks: [TextBlock], lines: [TextLine], fullText: String) {
        let lines = SpatialEngine.clusterRows(blocks)
        let textLines = lines.map { $0.text }
        let fullText = rawText ?? textLines.joined(separator: "\n")
        return (blocks, lines, fullText)
    }
    
    /// 2. Profil Tespiti:
    /// VendorProfile.applyRules çağrılmadan önce tek sefer çalışır ve
    /// `applies(to:)` fonksiyonu true dönen ilk profili seçer.
    /// Profil bulunamazsa `nil` döner ve pipeline generic modda devam eder.
    private func detectProfile(fromFullText fullText: String) -> VendorProfile? {
        let textLower = fullText.lowercased()
        for profile in profiles {
            if profile.applies(to: textLower) {
                print("✅ Profil Tespit Edildi: \(profile.vendorName)")
                return profile
            }
        }
        print("ℹ️ Profil bulunamadı, generic pipeline kullanılacak.")
        return nil
    }
    
    /// 3. Strateji Çalıştırma:
    /// Vendor, fatura detayları, ürünler ve finansal stratejileri sırasıyla uygular.
    private func runStrategies(context: ExtractionContext, invoice: inout Invoice) {
        for strategy in strategies {
            strategy.extract(context: context, invoice: &invoice)
        }
    }
    
    /// 4. Vendor Post-Processing:
    /// Seçilen profilin applyRules fonksiyonunu çalıştırır; profil yoksa hiçbir şey yapmaz.
    private func applyVendorRules(profile: VendorProfile?, invoice: inout Invoice, context: ExtractionContext) {
        guard let profile = profile else { return }
        profile.applyRules(to: &invoice, rawText: context.rawText, blocks: context.blocks)
    }
    
    /// 5. Debug Region Üretimi:
    /// Satıcı, tablo, toplam, tarih, KDV ve ara toplam bölgelerini hesaplayıp invoice.debugRegions'a ekler.
    private func buildDebugRegions(invoice: inout Invoice, blocks: [TextBlock], lines: [TextLine]) {
        addSellerRegion(to: &invoice, lines: lines)
        addTableRegion(to: &invoice, lines: lines)
        addTotalRegion(to: &invoice, blocks: blocks)
        addDateRegion(to: &invoice, blocks: blocks)
        addTaxRegion(to: &invoice, blocks: blocks)
        addSubTotalRegion(to: &invoice, blocks: blocks)
    }
    
    /// 6. Confidence Hesabı:
    /// Alan bazlı skorları, tanımlı ağırlıklarla birleştirerek 0–1 arası bir güven skoru üretir.
    private func computeConfidence(for invoice: Invoice) -> Float {
        let weights = ConfidenceWeights.self
        
        // Temel alanlar (merchantName, merchantTaxID, totalAmount, ettn)
        let basicScore = basicFieldsScore(for: invoice)
        // Finansal tutarlılık (total/subTotal/tax ilişkisi)
        let financialScore = financialScore(for: invoice)
        // Kalite metriği (fatura no formatı, tarih geçerliliği)
        let qualityScore = qualityScore(for: invoice)
        // Ürün kalemleri (items)
        let itemsScore = itemsScore(for: invoice)
        
        // Matematiksel form:
        // score = basic * wb + financial * wf + quality * wq + items * wi
        var score =
            basicScore     * weights.basicFields +
            financialScore * weights.financial +
            qualityScore   * weights.quality +
            itemsScore     * weights.items
        
        // Toplam tutar 0 ise, güveni yarıya indir (kritik alan eksikliği cezası)
        if invoice.totalAmount == 0 {
            score *= 0.5
        }
        
        // Skoru 0–1 aralığına sıkıştır
        return min(max(score, 0.0), 1.0)
    }
    
    // MARK: - Confidence Subscores
    
    /// Temel alanlar için skor: merchantName, merchantTaxID, totalAmount, ETTN uzunluğu.
    private func basicFieldsScore(for invoice: Invoice) -> Float {
        var points: Float = 0.0
        var checks: Float = 0.0
        
        checks += 1; if !invoice.merchantName.isEmpty { points += 1 }
        checks += 1; if !invoice.merchantTaxID.isEmpty { points += 1 }
        checks += 1; if invoice.totalAmount > 0 { points += 1 }
        checks += 1; if invoice.ettn.count > 20 { points += 1 }
        
        return checks > 0 ? (points / checks) : 0.0
    }
    
    /// Finansal tutarlılık skoru: toplam, ara toplam ve KDV ilişkisinin kontrolü.
    private func financialScore(for invoice: Invoice) -> Float {
        guard invoice.totalAmount > 0 else { return 0.0 }
        
        var score: Float = 0.0
        score += 1.0 // toplam mevcut
        
        if invoice.subTotal > 0 && invoice.taxAmount > 0 {
            let calculatedTotal = invoice.subTotal + invoice.taxAmount
            let difference = abs(invoice.totalAmount - calculatedTotal)
            // %1 tolerans içinde ise ek puan
            if difference < invoice.totalAmount * 0.01 {
                score += 0.5
            }
        }
        
        // Maksimum 1.0 olacak şekilde normalize et
        return min(score / 1.5, 1.0)
    }
    
    /// Kalite skoru: fatura numarası formatı ve tarih geçerliliği.
    private func qualityScore(for invoice: Invoice) -> Float {
        var score: Float = 0.0
        
        if !invoice.invoiceNo.isEmpty {
            score += 0.5
            if invoice.invoiceNo.count >= 14 {
                score += 0.5
            }
        }
        
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDate(invoice.invoiceDate, inSameDayAs: now) || invoice.invoiceDate < now {
            score += 0.5
        }
        
        return min(score / 1.5, 1.0)
    }
    
    /// Ürün kalemleri skoru: en az bir item varsa 1, yoksa 0.
    private func itemsScore(for invoice: Invoice) -> Float {
        return invoice.items.isEmpty ? 0.0 : 1.0
    }
    
    /// Confidence ağırlıkları:
    /// Temel Alanlar (%40), Finansal (%30), Kalite (%20), Ürünler (%10)
    private struct ConfidenceWeights {
        static let basicFields: Float = 0.4
        static let financial:   Float = 0.3
        static let quality:     Float = 0.2
        static let items:       Float = 0.1
    }
    
    // MARK: - 🕵️‍♂️ Debug / Görselleştirme Helper’ları
    
    /// Satıcı bölgesi:
    /// Splitter keyword'ünden ("SAYIN", "ALICI" vb.) önceki satırların birleşimi; splitter yoksa ilk %20'lik kısım.
    private func addSellerRegion(to invoice: inout Invoice, lines: [TextLine]) {
        if let splitIndex = lines.firstIndex(where: { line in
            RegexPatterns.Keywords.splitters.contains(where: { line.text.uppercased().contains($0) })
        }) {
            let sellerLines = Array(lines.prefix(splitIndex))
            if let rect = InvoiceParserHelper.calculateUnionRect(of: sellerLines) {
                invoice.debugRegions.append(OCRRegion(type: .seller, rect: rect))
            }
        } else {
            let count = max(1, Int(Double(lines.count) * 0.20))
            let sellerLines = Array(lines.prefix(count))
            if let rect = InvoiceParserHelper.calculateUnionRect(of: sellerLines) {
                invoice.debugRegions.append(OCRRegion(type: .seller, rect: rect))
            }
        }
    }
    
    /// Tablo bölgesi:
    /// İlk tablo başlığından (tableHeaders) ilk tablo sonuna (tableFooters) kadar olan satırlar.
    private func addTableRegion(to invoice: inout Invoice, lines: [TextLine]) {
        guard let headerIndex = lines.firstIndex(where: { line in
            RegexPatterns.Keywords.tableHeaders.contains(where: { line.text.uppercased().contains($0) })
        }) else { return }
        
        let footerIndex = lines.indices.first(where: { index in
            index > headerIndex &&
            RegexPatterns.Keywords.tableFooters.contains(where: { lines[index].text.uppercased().contains($0) })
        }) ?? lines.count
        
        let endIndex = min(footerIndex + 1, lines.count)
        let tableLines = Array(lines[headerIndex..<endIndex])
        
        if let rect = InvoiceParserHelper.calculateUnionRect(of: tableLines) {
            invoice.debugRegions.append(OCRRegion(type: .table, rect: rect))
        }
    }
    
    /// Toplam tutar bölgesi:
    /// invoice.totalAmount ile tutarı eşleşen ilk blok.
    private func addTotalRegion(to invoice: inout Invoice, blocks: [TextBlock]) {
        guard invoice.totalAmount > 0 else { return }
        
        for block in blocks {
            if let amount = InvoiceParserHelper.extractAmount(from: block.text),
               abs(amount - invoice.totalAmount) < 0.01 {
                invoice.debugRegions.append(OCRRegion(type: .total, rect: block.frame))
                break
            }
        }
    }
    
    /// Tarih bölgesi:
    /// Tarih regex’i ile eşleşen ilk blok; genelde header sağ bölgede yer alır.
    private func addDateRegion(to invoice: inout Invoice, blocks: [TextBlock]) {
        for block in blocks {
            if InvoiceParserHelper.containsDate(block.text) {
                invoice.debugRegions.append(OCRRegion(type: .date, rect: block.frame))
                break
            }
        }
    }
    
    /// KDV bölgesi:
    /// invoice.taxAmount ile tutarı eşleşen ilk blok.
    private func addTaxRegion(to invoice: inout Invoice, blocks: [TextBlock]) {
        guard invoice.taxAmount > 0 else { return }
        
        for block in blocks {
            if let amount = InvoiceParserHelper.extractAmount(from: block.text),
               abs(amount - invoice.taxAmount) < 0.01 {
                invoice.debugRegions.append(OCRRegion(type: .tax, rect: block.frame))
                break
            }
        }
    }
    
    /// Ara toplam (matrah) bölgesi:
    /// invoice.subTotal ile tutarı eşleşen ilk blok.
    private func addSubTotalRegion(to invoice: inout Invoice, blocks: [TextBlock]) {
        guard invoice.subTotal > 0 else { return }
        
        for block in blocks {
            if let amount = InvoiceParserHelper.extractAmount(from: block.text),
               abs(amount - invoice.subTotal) < 0.01 {
                invoice.debugRegions.append(OCRRegion(type: .subTotal, rect: block.frame))
                break
            }
        }
    }
}
