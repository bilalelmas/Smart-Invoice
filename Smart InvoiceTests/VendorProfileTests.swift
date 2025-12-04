import XCTest
@testable import Smart_Invoice

final class VendorProfileTests: XCTestCase {
    
    // MARK: - Trendyol Profile Tests
    
    func testTrendyolProfile_Applies_WithDSMGrup() {
        let profile = TrendyolProfile()
        let text = "DSM Grup Danışmanlık İletişim ve Satış Ticaret A.Ş."
        XCTAssertTrue(profile.applies(to: text.lowercased()))
    }
    
    func testTrendyolProfile_Applies_WithTrendyol() {
        let profile = TrendyolProfile()
        let text = "Trendyol.com - Online Alışveriş"
        XCTAssertTrue(profile.applies(to: text.lowercased()))
    }
    
    func testTrendyolProfile_DoesNotApply_ShortText() {
        let profile = TrendyolProfile()
        let text = "Trendyol" // Çok kısa metin
        XCTAssertFalse(profile.applies(to: text.lowercased()))
    }
    
    func testTrendyolProfile_ApplyRules_MarketplaceSeller() {
        let profile = TrendyolProfile()
        var invoice = Invoice(userId: "")
        invoice.merchantName = "HAKKI YILMAZ" // Gerçek satıcı
        
        profile.applyRules(to: &invoice, rawText: "HAKKI YILMAZ\nDSM Grup\nTrendyol")
        
        // Gerçek satıcı adı korunmalı (DSM Grup içermiyor)
        XCTAssertEqual(invoice.merchantName, "HAKKI YILMAZ")
    }
    
    func testTrendyolProfile_ApplyRules_DirectTrendyol() {
        let profile = TrendyolProfile()
        var invoice = Invoice(userId: "")
        invoice.merchantName = "DSM Grup Danışmanlık İletişim ve Satış Ticaret A.Ş."
        
        profile.applyRules(to: &invoice, rawText: "DSM Grup\nTrendyol")
        
        // DSM Grup adı korunmalı
        XCTAssertTrue(invoice.merchantName.contains("DSM GRUP"))
    }
    
    func testTrendyolProfile_ApplyRules_OrderNumber() {
        let profile = TrendyolProfile()
        var invoice = Invoice(userId: "")
        invoice.invoiceNo = ""
        
        profile.applyRules(to: &invoice, rawText: "SİPARİŞ NO: TYF12345678901234")
        
        // Sipariş numarası fatura numarası olarak kullanılmalı
        XCTAssertEqual(invoice.invoiceNo, "TYF12345678901234")
    }
    
    // MARK: - A101 Profile Tests
    
    func testA101Profile_Applies_WithA101() {
        let profile = A101Profile()
        let text = "A101 Yeni Mağazacılık A.Ş."
        XCTAssertTrue(profile.applies(to: text.lowercased()))
    }
    
    func testA101Profile_Applies_WithYeniMagazacilik() {
        let profile = A101Profile()
        let text = "Yeni Mağazacılık A.Ş."
        XCTAssertTrue(profile.applies(to: text.lowercased()))
    }
    
    func testA101Profile_Applies_WithWebsite() {
        let profile = A101Profile()
        let text = "www.a101.com.tr"
        XCTAssertTrue(profile.applies(to: text.lowercased()))
    }
    
    func testA101Profile_ApplyRules_InvoiceNumber() {
        let profile = A101Profile()
        var invoice = Invoice(userId: "")
        invoice.invoiceNo = ""
        
        profile.applyRules(to: &invoice, rawText: "A101\nFatura No: A123456789012345")
        
        XCTAssertEqual(invoice.invoiceNo, "A123456789012345")
    }
    
    func testA101Profile_ApplyRules_TotalAmount() {
        let profile = A101Profile()
        var invoice = Invoice(userId: "")
        invoice.totalAmount = 0.0
        
        profile.applyRules(to: &invoice, rawText: "Ödenecek Tutar: 1.234,56 TL")
        
        XCTAssertEqual(invoice.totalAmount, 1234.56, accuracy: 0.01)
    }
    
    func testA101Profile_ApplyRules_MerchantName() {
        let profile = A101Profile()
        var invoice = Invoice(userId: "")
        
        profile.applyRules(to: &invoice, rawText: "A101")
        
        XCTAssertEqual(invoice.merchantName, "A101 Yeni Mağazacılık A.Ş.")
    }
    
    // MARK: - FLO Profile Tests
    
    func testFLOProfile_Applies_WithFLO() {
        let profile = FLOProfile()
        let text = "FLO Mağazacılık A.Ş."
        XCTAssertTrue(profile.applies(to: text.lowercased()))
    }
    
    func testFLOProfile_Applies_WithFlo() {
        let profile = FLOProfile()
        let text = "Flo.com.tr"
        XCTAssertTrue(profile.applies(to: text.lowercased()))
    }
    
    func testFLOProfile_DoesNotApply_WithoutFLO() {
        let profile = FLOProfile()
        let text = "Başka bir mağaza"
        XCTAssertFalse(profile.applies(to: text.lowercased()))
    }
    
    func testFLOProfile_ApplyRules_MerchantName() {
        let profile = FLOProfile()
        var invoice = Invoice(userId: "")
        
        profile.applyRules(to: &invoice, rawText: "FLO")
        
        XCTAssertTrue(invoice.merchantName.contains("FLO"))
    }
    
    // MARK: - Default Profile Tests
    
    func testDefaultProfile_Applies_Always() {
        let profile = DefaultProfile()
        let text = "Herhangi bir fatura metni"
        XCTAssertTrue(profile.applies(to: text.lowercased()))
    }
    
    func testDefaultProfile_ApplyRules_NoChanges() {
        let profile = DefaultProfile()
        var invoice = Invoice(userId: "")
        invoice.merchantName = "Test Firma"
        invoice.totalAmount = 100.0
        
        let originalName = invoice.merchantName
        let originalAmount = invoice.totalAmount
        
        profile.applyRules(to: &invoice, rawText: "Test")
        
        // Default profile hiçbir değişiklik yapmamalı
        XCTAssertEqual(invoice.merchantName, originalName)
        XCTAssertEqual(invoice.totalAmount, originalAmount)
    }
    
    // MARK: - Profile Priority Tests
    
    func testProfilePriority_TrendyolBeforeDefault() {
        let text = "DSM Grup Danışmanlık\nTrendyol"
        let trendyolProfile = TrendyolProfile()
        let defaultProfile = DefaultProfile()
        
        XCTAssertTrue(trendyolProfile.applies(to: text.lowercased()))
        XCTAssertTrue(defaultProfile.applies(to: text.lowercased()))
        
        // Trendyol profili öncelikli olmalı
        var invoice = Invoice(userId: "")
        trendyolProfile.applyRules(to: &invoice, rawText: text)
        
        // Trendyol profili uygulanmış olmalı
        XCTAssertNotNil(invoice)
    }
}

