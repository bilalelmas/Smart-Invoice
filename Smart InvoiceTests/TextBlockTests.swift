import XCTest
@testable import Smart_Invoice
import CoreGraphics

final class TextBlockTests: XCTestCase {
    
    // MARK: - Coordinate Conversion Tests
    
    func testConvertVisionToUIKit_BottomLeftToTopLeft() {
        // Vision: (0,0) sol alt, (1,1) sağ üst
        // UIKit: (0,0) sol üst, (1,1) sağ alt
        
        // Vision'da sol alt köşede bir blok (y=0, height=0.1)
        let visionRect = CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.1)
        let uikitRect = TextBlock.convertVisionToUIKit(visionRect)
        
        // UIKit'de sol üst köşede olmalı
        XCTAssertEqual(uikitRect.origin.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(uikitRect.origin.y, 0.9, accuracy: 0.001) // 1 - (0 + 0.1) = 0.9
        XCTAssertEqual(uikitRect.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(uikitRect.height, 0.1, accuracy: 0.001)
    }
    
    func testConvertVisionToUIKit_TopRight() {
        // Vision'da sağ üst köşede bir blok (y=0.9, height=0.1)
        let visionRect = CGRect(x: 0.5, y: 0.9, width: 0.5, height: 0.1)
        let uikitRect = TextBlock.convertVisionToUIKit(visionRect)
        
        // UIKit'de sol üst köşede olmalı (y=0)
        XCTAssertEqual(uikitRect.origin.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(uikitRect.origin.y, 0.0, accuracy: 0.001) // 1 - (0.9 + 0.1) = 0.0
        XCTAssertEqual(uikitRect.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(uikitRect.height, 0.1, accuracy: 0.001)
    }
    
    func testConvertVisionToUIKit_Center() {
        // Vision'da ortada bir blok (y=0.4, height=0.2)
        let visionRect = CGRect(x: 0.2, y: 0.4, width: 0.6, height: 0.2)
        let uikitRect = TextBlock.convertVisionToUIKit(visionRect)
        
        // UIKit'de ortada olmalı (y=0.4)
        XCTAssertEqual(uikitRect.origin.x, 0.2, accuracy: 0.001)
        XCTAssertEqual(uikitRect.origin.y, 0.4, accuracy: 0.001) // 1 - (0.4 + 0.2) = 0.4
        XCTAssertEqual(uikitRect.width, 0.6, accuracy: 0.001)
        XCTAssertEqual(uikitRect.height, 0.2, accuracy: 0.001)
    }
    
    func testConvertVisionToUIKit_RoundTrip() {
        // Vision → UIKit → Vision dönüşümü (tam tersi yok ama test edilebilir)
        let originalVision = CGRect(x: 0.1, y: 0.3, width: 0.4, height: 0.2)
        let uikitRect = TextBlock.convertVisionToUIKit(originalVision)
        
        // UIKit rect'inin geçerli olduğunu kontrol et
        XCTAssertGreaterThanOrEqual(uikitRect.origin.x, 0.0)
        XCTAssertGreaterThanOrEqual(uikitRect.origin.y, 0.0)
        XCTAssertLessThanOrEqual(uikitRect.origin.x + uikitRect.width, 1.0)
        XCTAssertLessThanOrEqual(uikitRect.origin.y + uikitRect.height, 1.0)
    }
    
    // MARK: - TextBlock Properties Tests
    
    func testTextBlock_Properties() {
        let frame = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05)
        let block = TextBlock(text: "Test", frame: frame, confidence: 0.95)
        
        XCTAssertEqual(block.text, "Test")
        XCTAssertEqual(block.frame, frame)
        XCTAssertEqual(block.confidence, 0.95, accuracy: 0.001)
        XCTAssertEqual(block.x, 0.1, accuracy: 0.001)
        XCTAssertEqual(block.y, 0.2, accuracy: 0.001)
        XCTAssertEqual(block.width, 0.3, accuracy: 0.001)
        XCTAssertEqual(block.height, 0.05, accuracy: 0.001)
        XCTAssertEqual(block.midY, 0.225, accuracy: 0.001) // 0.2 + 0.05/2
    }
    
    // MARK: - TextLine Creation Tests
    
    func testTextLine_SingleBlock() {
        let block = TextBlock(text: "Hello", frame: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.05), confidence: 0.9)
        let line = TextLine(blocks: [block])
        
        XCTAssertEqual(line.blocks.count, 1)
        XCTAssertEqual(line.text, "Hello")
        XCTAssertEqual(line.frame, block.frame)
    }
    
    func testTextLine_MultipleBlocks_Sorted() {
        let block1 = TextBlock(text: "World", frame: CGRect(x: 0.5, y: 0.2, width: 0.2, height: 0.05), confidence: 0.9)
        let block2 = TextBlock(text: "Hello", frame: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.05), confidence: 0.9)
        
        let line = TextLine(blocks: [block1, block2])
        
        // Bloklar soldan sağa sıralanmalı
        XCTAssertEqual(line.blocks.count, 2)
        XCTAssertEqual(line.blocks[0].text, "Hello") // Sol taraftaki
        XCTAssertEqual(line.blocks[1].text, "World") // Sağ taraftaki
        XCTAssertEqual(line.text, "Hello World")
    }
    
    func testTextLine_BoundingBox() {
        let block1 = TextBlock(text: "A", frame: CGRect(x: 0.1, y: 0.2, width: 0.1, height: 0.05), confidence: 0.9)
        let block2 = TextBlock(text: "B", frame: CGRect(x: 0.3, y: 0.2, width: 0.1, height: 0.05), confidence: 0.9)
        let block3 = TextBlock(text: "C", frame: CGRect(x: 0.5, y: 0.2, width: 0.1, height: 0.05), confidence: 0.9)
        
        let line = TextLine(blocks: [block1, block2, block3])
        
        // Bounding box tüm blokları kapsamalı
        XCTAssertEqual(line.frame.origin.x, 0.1, accuracy: 0.001)
        XCTAssertEqual(line.frame.origin.y, 0.2, accuracy: 0.001)
        XCTAssertEqual(line.frame.width, 0.5, accuracy: 0.001) // 0.1 + 0.1 + 0.1 + 0.2 (gaps)
        XCTAssertEqual(line.frame.height, 0.05, accuracy: 0.001)
    }
    
    func testTextLine_DifferentYPositions() {
        // Farklı Y pozisyonlarına sahip bloklar aynı satırda olmamalı
        // (Bu test TextLine'ın kendisini test eder, gerçek gruplama InvoiceParser'da yapılır)
        let block1 = TextBlock(text: "Line1", frame: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05), confidence: 0.9)
        let block2 = TextBlock(text: "Line2", frame: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.05), confidence: 0.9)
        
        let line = TextLine(blocks: [block1, block2])
        
        // TextLine oluşturulabilir ama bounding box her ikisini de kapsamalı
        XCTAssertEqual(line.blocks.count, 2)
        XCTAssertEqual(line.frame.origin.y, 0.1, accuracy: 0.001) // En üst
        XCTAssertEqual(line.frame.height, 0.15, accuracy: 0.001) // 0.1 + 0.05
    }
    
    func testTextLine_EmptyBlocks() {
        let line = TextLine(blocks: [])
        
        XCTAssertEqual(line.blocks.count, 0)
        XCTAssertEqual(line.text, "")
        // Empty blocks için frame tanımsız olabilir, bu test edge case'i kontrol eder
    }
}

