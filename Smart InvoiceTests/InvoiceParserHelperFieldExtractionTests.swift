import XCTest
@testable import Smart_Invoice

final class InvoiceParserHelperFieldExtractionTests: XCTestCase {
    
    func testExtractAmount_singleAmount() {
        let text = "Toplam Tutar: 809,96 TL"
        let amount = InvoiceParserHelper.extractAmount(from: text)
        XCTAssertEqual(amount, 809.96, accuracy: 0.001)
    }
    
    func testExtractAllAmounts_multipleMatches() {
        let text = "Ara Toplam 100,00 TL\nKDV 18,00 TL\nGenel Toplam 118,00 TL"
        let amounts = InvoiceParserHelper.extractAllAmounts(from: text)
        XCTAssertEqual(amounts.count, 3)
        XCTAssertEqual(amounts[0], 100.0, accuracy: 0.001)
        XCTAssertEqual(amounts[1], 18.0, accuracy: 0.001)
        XCTAssertEqual(amounts[2], 118.0, accuracy: 0.001)
    }
    
    func testExtractDate_differentFormats() {
        let text1 = "Fatura Tarihi: 01.02.2024"
        let text2 = "Düzenleme Tarihi 1/2/2024"
        
        let date1 = InvoiceParserHelper.extractDate(from: text1)
        let date2 = InvoiceParserHelper.extractDate(from: text2)
        
        XCTAssertNotNil(date1)
        XCTAssertNotNil(date2)
    }
    
    func testExtractETTN_withNoise() {
        let ettn = "ETTN: 123e4567-e89b-12d3-a456-426614174000"
        let text = "Bu bir test satırıdır \(ettn) ekstra yazı"
        
        let extracted = InvoiceParserHelper.extractETTN(from: text)
        XCTAssertEqual(extracted, "123e4567-e89b-12d3-a456-426614174000")
    }
    
    func testExtractInvoiceNo_standardAndA101() {
        let standard = "FATURA NO: ABC2023123456789"
        let a101 = "Fatura No A123456789012345"
        
        let standardResult = InvoiceParserHelper.extractInvoiceNo(from: standard)
        let a101Result = InvoiceParserHelper.extractInvoiceNo(from: a101)
        
        XCTAssertEqual(standardResult, "ABC2023123456789")
        XCTAssertEqual(a101Result, "A123456789012345")
    }
    
    func testExtractVKN_and_TCKN() {
        let text = "VKN: 1234567890\nTCKN 12345678901"
        
        let vkn = InvoiceParserHelper.extractVKN(from: text)
        let tckn = InvoiceParserHelper.extractTCKN(from: text)
        
        XCTAssertEqual(vkn, "1234567890")
        XCTAssertEqual(tckn, "12345678901")
    }
    
    func testDetectTaxRate_variousPatterns() {
        let text18 = "Hesaplanan KDV %18"
        let text20 = "KDV 20%"
        
        let rate18 = InvoiceParserHelper.detectTaxRate(from: text18)
        let rate20 = InvoiceParserHelper.detectTaxRate(from: text20)
        
        XCTAssertEqual(rate18, 0.18, accuracy: 0.0001)
        XCTAssertEqual(rate20, 0.20, accuracy: 0.0001)
    }
}


