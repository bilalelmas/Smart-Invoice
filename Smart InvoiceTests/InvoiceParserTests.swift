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
        // Mock TextBlock verisi
        let blocks = [
            TextBlock(text: "Trendyol", boundingBox: .zero),
            TextBlock(text: "Satıcı: DSM Grup", boundingBox: .zero),
            TextBlock(text: "Tarih: 01.01.2024", boundingBox: .zero)
        ]
        
        // Private metodları test etmek zor olduğu için, 
        // ya internal yapmalıyız ya da public arayüzden test etmeliyiz.
        // Şimdilik VendorProfileProtocol üzerinden test edelim.
        
        let profile = TrendyolProfile()
        let fullText = blocks.map { $0.text }.joined(separator: "\n")
        
        XCTAssertTrue(profile.isMatch(text: fullText))
    }

    func testA101Detection() throws {
        let blocks = [
            TextBlock(text: "A101", boundingBox: .zero),
            TextBlock(text: "Yeni Mağazacılık A.Ş.", boundingBox: .zero),
            TextBlock(text: "Fatura No: A123456789012345", boundingBox: .zero)
        ]
        
        let profile = A101Profile()
        let fullText = blocks.map { $0.text }.joined(separator: "\n")
        
        XCTAssertTrue(profile.isMatch(text: fullText))
    }
    
    func testA101InvoiceNumberParsing() throws {
        let blocks = [
            TextBlock(text: "A101", boundingBox: .zero),
            TextBlock(text: "Fatura No: A123456789012345", boundingBox: .zero)
        ]
        
        let profile = A101Profile()
        let invoice = profile.parse(textBlocks: blocks)
        
        XCTAssertEqual(invoice?.invoiceNo, "A123456789012345")
    }
}
