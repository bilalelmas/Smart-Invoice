import XCTest
@testable import Smart_Invoice

final class InvoiceParserTests: XCTestCase {

    var parser: InvoiceParser!

    override func setUpWithError() throws {
        parser = InvoiceParser()
    }

    override func tearDownWithError() throws {
        parser = nil
    }

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
        
        var invoice = Invoice()
        profile.applyRules(to: &invoice, rawText: text)
        
        XCTAssertEqual(invoice.invoiceNo, "A123456789012345")
    }
}
