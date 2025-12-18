import XCTest
@testable import Smart_Invoice

final class InvoiceParserTests: XCTestCase {

    var parser: InvoiceParser!

    override func setUpWithError() throws {
        parser = InvoiceParser.shared
    }

    override func tearDownWithError() throws {
        parser = nil
    }

    // MARK: - Vendor Profile Tests
    
    func testTrendyolDetection() throws {
        let text = "Trendyol\nSatıcı: DSM Grup\nTarih: 01.01.2024"
        let profile = TrendyolProfile()
        XCTAssertTrue(profile.applies(to: text.lowercased()))
    }

    func testA101Detection() throws {
        let text = "A101\nYeni Mağazacılık A.Ş.\nFatura No: A123456789012345"
        let profile = A101Profile()
        XCTAssertTrue(profile.applies(to: text.lowercased()))
    }
    
    func testA101InvoiceNumberParsing() throws {
        let text = "A101\nFatura No: A123456789012345"
        let profile = A101Profile()
        
        var invoice = Invoice(userId: "")
        profile.applyRules(to: &invoice, rawText: text)
        
        XCTAssertEqual(invoice.invoiceNo, "A123456789012345")
    }
    
    // MARK: - Date Extraction Tests
    
    func testDateExtraction_DDMMYYYY() async throws {
        let text = "Fatura Tarihi: 15.03.2024\nToplam: 100,00 TL"
        let invoice = try await parser.parse(blocks: [], rawText: text)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.locale = Locale(identifier: "tr_TR")
        let expectedDate = formatter.date(from: "15.03.2024")!
        
        XCTAssertTrue(Calendar.current.isDate(invoice.invoiceDate, inSameDayAs: expectedDate))
    }
    
    func testDateExtraction_DDMMYYYY_Slash() async throws {
        let text = "Tarih: 15/03/2024\nToplam: 200,00 TL"
        let invoice = try await parser.parse(blocks: [], rawText: text)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.locale = Locale(identifier: "tr_TR")
        let expectedDate = formatter.date(from: "15/03/2024")!
        
        XCTAssertTrue(Calendar.current.isDate(invoice.invoiceDate, inSameDayAs: expectedDate))
    }
    
    // MARK: - Amount Extraction Tests
    
    func testAmountExtraction_Standard() async throws {
        let text = "Toplam Tutar: 1.234,56 TL\nKDV: 222,22 TL"
        let invoice = try await parser.parse(blocks: [], rawText: text)
        
        XCTAssertEqual(invoice.totalAmount, 1234.56, accuracy: 0.01)
    }
    
    func testAmountExtraction_WithComma() async throws {
        let text = "Ödenecek Tutar: 500,50 TL"
        let invoice = try await parser.parse(blocks: [], rawText: text)
        
        XCTAssertEqual(invoice.totalAmount, 500.50, accuracy: 0.01)
    }
    
    func testAmountExtraction_MultipleAmounts() async throws {
        let text = "Ara Toplam: 100,00 TL\nKDV: 18,00 TL\nGenel Toplam: 118,00 TL"
        let invoice = try await parser.parse(blocks: [], rawText: text)
        
        XCTAssertEqual(invoice.totalAmount, 118.00, accuracy: 0.01)
    }
    
    // MARK: - Merchant Name Extraction Tests
    
    func testMerchantNameExtraction_Standard() async throws {
        let text = """
        ABC Şirketi A.Ş.
        Adres: İstanbul
        VKN: 1234567890
        """
        let invoice = try await parser.parse(blocks: [], rawText: text)
        
        XCTAssertTrue(invoice.merchantName.contains("ABC"))
    }
    
    // MARK: - ETTN Extraction Tests
    
    func testETTNExtraction() async throws {
        let text = "ETTN: 12345678-1234-1234-1234-123456789012"
        let invoice = try await parser.parse(blocks: [], rawText: text)
        
        XCTAssertEqual(invoice.ettn, "12345678-1234-1234-1234-123456789012")
    }
    
    // MARK: - Invoice Number Extraction Tests
    
    func testInvoiceNumberExtraction_Standard() async throws {
        let text = "Fatura No: INV-2024-001"
        let invoice = try await parser.parse(blocks: [], rawText: text)
        
        XCTAssertTrue(invoice.invoiceNo.contains("INV"))
    }
    
    // MARK: - Spatial Analysis Tests
    
    func testSpatialAnalysis_BlockGrouping() async throws {
        // Aynı Y koordinatına sahip bloklar aynı satırda olmalı
        let blocks: [TextBlock] = [
            TextBlock(text: "Satıcı", frame: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.02), confidence: 0.9),
            TextBlock(text: "ABC", frame: CGRect(x: 0.3, y: 0.1, width: 0.1, height: 0.02), confidence: 0.9),
            TextBlock(text: "Tarih", frame: CGRect(x: 0.1, y: 0.15, width: 0.1, height: 0.02), confidence: 0.9),
            TextBlock(text: "01.01.2024", frame: CGRect(x: 0.3, y: 0.15, width: 0.1, height: 0.02), confidence: 0.9)
        ]
        
        let invoice = try await parser.parse(blocks: blocks, rawText: nil)
        
        // En azından parse başarılı olmalı
        XCTAssertNotNil(invoice)
    }
    
    // MARK: - Confidence Score Tests
    
    func testConfidenceScore_CompleteInvoice() async throws {
        let text = """
        ABC Şirketi A.Ş.
        VKN: 1234567890
        Fatura No: INV-001
        Tarih: 01.01.2024
        ETTN: 12345678-1234-1234-1234-123456789012
        Toplam: 100,00 TL
        """
        let invoice = try await parser.parse(blocks: [], rawText: text)
        
        // Confidence score 0 ile 1 arasında olmalı
        XCTAssertGreaterThanOrEqual(invoice.confidenceScore, 0.0)
        XCTAssertLessThanOrEqual(invoice.confidenceScore, 1.0)
    }
    
    // MARK: - Pipeline Integration Tests
    
    func testPipeline_TrendyolProfileWithBlocks() async throws {
        // Trendyol anahtar kelimeleri + basit footer
        let blocks: [TextBlock] = [
            TextBlock(text: "DSM GRUP DANISMANLIK", frame: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.02), confidence: 0.9),
            TextBlock(text: "TRENDYOL", frame: CGRect(x: 0.1, y: 0.12, width: 0.3, height: 0.02), confidence: 0.9),
            TextBlock(text: "FATURA NO ABC2023123456789", frame: CGRect(x: 0.6, y: 0.1, width: 0.3, height: 0.02), confidence: 0.9),
            TextBlock(text: "FATURA TARİHİ 15.03.2024", frame: CGRect(x: 0.6, y: 0.12, width: 0.3, height: 0.02), confidence: 0.9),
            TextBlock(text: "ETTN 12345678-1234-1234-1234-123456789012", frame: CGRect(x: 0.6, y: 0.14, width: 0.35, height: 0.02), confidence: 0.9),
            TextBlock(text: "MAL HİZMET", frame: CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.02), confidence: 0.9),
            TextBlock(text: "ÜRÜN ADI", frame: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.02), confidence: 0.9),
            TextBlock(text: "TOPLAM", frame: CGRect(x: 0.7, y: 0.3, width: 0.2, height: 0.02), confidence: 0.9),
            TextBlock(text: "Ürün X 100,00 TL", frame: CGRect(x: 0.1, y: 0.35, width: 0.8, height: 0.02), confidence: 0.9),
            TextBlock(text: "GENEL TOPLAM 100,00 TL", frame: CGRect(x: 0.6, y: 0.8, width: 0.3, height: 0.02), confidence: 0.9)
        ]
        
        let rawText = blocks.map { $0.text }.joined(separator: "\n")
        let invoice = try await parser.parse(blocks: blocks, rawText: rawText)
        
        XCTAssertTrue(invoice.merchantName.contains("DSM") || invoice.merchantName.contains("TRENDYOL"))
        XCTAssertFalse(invoice.invoiceNo.isEmpty)
        XCTAssertFalse(invoice.ettn.isEmpty)
        XCTAssertGreaterThan(invoice.totalAmount, 0.0)
        XCTAssertGreaterThan(invoice.confidenceScore, 0.0)
    }
    
    func testPipeline_A101ProfileWithRawText() async throws {
        let text = """
        A101 Yeni Mağazacılık A.Ş.
        Fatura No: A123456789012345
        Tarih: 01.02.2024
        Ödenecek Tutar: 250,00 TL
        """
        
        let invoice = try await parser.parse(blocks: [], rawText: text)
        
        XCTAssertEqual(invoice.merchantName, "A101 Yeni Mağazacılık A.Ş.")
        XCTAssertEqual(invoice.invoiceNo, "A123456789012345")
        XCTAssertGreaterThan(invoice.totalAmount, 0.0)
        XCTAssertGreaterThan(invoice.confidenceScore, 0.0)
    }
    
    func testPipeline_GenericProfileFallback() async throws {
        let text = """
        XYZ Teknoloji Ltd. Şti.
        Adres: İstanbul
        Fatura No: INV20240001
        Tarih: 05.04.2024
        Toplam: 150,00 TL
        """
        
        let invoice = try await parser.parse(blocks: [], rawText: text)
        
        // Hiçbir vendor profilinin apply'ine girmese bile temel alanlar dolu olmalı
        XCTAssertTrue(invoice.merchantName.contains("XYZ"))
        XCTAssertFalse(invoice.invoiceNo.isEmpty)
        XCTAssertGreaterThan(invoice.totalAmount, 0.0)
        XCTAssertGreaterThan(invoice.confidenceScore, 0.0)
    }
    
    // MARK: - Debug & Confidence Smoke Test
    
    func testDebugRegionsAndConfidence_WithBlocks() async throws {
        let blocks: [TextBlock] = [
            TextBlock(text: "ABC Şirketi A.Ş.", frame: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.02), confidence: 0.9),
            TextBlock(text: "SAYIN MÜŞTERİ", frame: CGRect(x: 0.1, y: 0.18, width: 0.4, height: 0.02), confidence: 0.9),
            TextBlock(text: "MAL HİZMET", frame: CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.02), confidence: 0.9),
            TextBlock(text: "TOPLAM", frame: CGRect(x: 0.7, y: 0.3, width: 0.2, height: 0.02), confidence: 0.9),
            TextBlock(text: "Ürün Y 80,00 TL", frame: CGRect(x: 0.1, y: 0.35, width: 0.8, height: 0.02), confidence: 0.9),
            TextBlock(text: "GENEL TOPLAM 80,00 TL", frame: CGRect(x: 0.6, y: 0.8, width: 0.3, height: 0.02), confidence: 0.9),
            TextBlock(text: "Tarih: 10.03.2024", frame: CGRect(x: 0.6, y: 0.15, width: 0.3, height: 0.02), confidence: 0.9)
        ]
        
        let rawText = blocks.map { $0.text }.joined(separator: "\n")
        let invoice = try await parser.parse(blocks: blocks, rawText: rawText)
        
        XCTAssertFalse(invoice.debugRegions.isEmpty)
        XCTAssertGreaterThan(invoice.confidenceScore, 0.0)
    }
    
    // MARK: - Error Handling Tests
    
    func testEmptyInput() async {
        do {
            _ = try await parser.parse(blocks: [], rawText: nil)
            XCTFail("Should throw emptyInput error")
        } catch let error as InvoiceParserError {
            XCTAssertEqual(error, InvoiceParserError.emptyInput)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
