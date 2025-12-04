import XCTest
@testable import Smart_Invoice
import UIKit

// MARK: - Mock Implementations

class MockOCRService: OCRServiceProtocol {
    var recognizedText: String = ""
    var isProcessing: Bool = false
    
    var mockResult: Result<Invoice, Error>?
    
    func recognizeText(from image: UIImage) async throws -> Invoice {
        if let result = mockResult {
            switch result {
            case .success(let invoice):
                return invoice
            case .failure(let error):
                throw error
            }
        }
        throw OCRServiceError.invalidImage
    }
}

class MockInvoiceParser: InvoiceParserProtocol {
    var mockInvoice: Invoice?
    var mockError: Error?
    
    func parse(blocks: [TextBlock], rawText: String?) async throws -> Invoice {
        if let error = mockError {
            throw error
        }
        return mockInvoice ?? Invoice(userId: "test")
    }
    
    func parse(text: String) async -> Invoice {
        return mockInvoice ?? Invoice(userId: "test")
    }
}

class MockFirebaseRepository: FirebaseInvoiceRepositoryProtocol {
    var savedInvoices: [Invoice] = []
    var mockError: Error?
    
    func addInvoice(_ invoice: Invoice) async throws -> String {
        if let error = mockError {
            throw error
        }
        let id = UUID().uuidString
        var newInvoice = invoice
        newInvoice.id = id
        savedInvoices.append(newInvoice)
        return id
    }
    
    func updateInvoice(_ invoice: Invoice) async throws {
        if let error = mockError {
            throw error
        }
        guard let id = invoice.id else {
            throw NSError(domain: "MockRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invoice ID required"])
        }
        if let index = savedInvoices.firstIndex(where: { $0.id == id }) {
            savedInvoices[index] = invoice
        }
    }
    
    func deleteInvoice(_ invoiceId: String) async throws {
        if let error = mockError {
            throw error
        }
        savedInvoices.removeAll { $0.id == invoiceId }
    }
    
    func getAllInvoices() async throws -> [Invoice] {
        if let error = mockError {
            throw error
        }
        return savedInvoices
    }
    
    func addTrainingData(_ trainingData: TrainingData) async throws {
        // Mock implementation - training data'yı kaydetme
    }
}

// MARK: - InvoiceViewModel Tests

final class InvoiceViewModelTests: XCTestCase {
    
    var viewModel: InvoiceViewModel!
    var mockOCRService: MockOCRService!
    var mockParser: MockInvoiceParser!
    var mockRepository: MockFirebaseRepository!
    
    override func setUpWithError() throws {
        mockOCRService = MockOCRService()
        mockParser = MockInvoiceParser()
        mockRepository = MockFirebaseRepository()
        
        viewModel = InvoiceViewModel(
            ocrService: mockOCRService,
            invoiceParser: mockParser,
            repository: mockRepository
        )
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        mockOCRService = nil
        mockParser = nil
        mockRepository = nil
    }
    
    // MARK: - scanInvoice Tests
    
    @MainActor
    func testScanInvoice_Success() async {
        let testInvoice = Invoice(userId: "test")
        testInvoice.merchantName = "Test Merchant"
        testInvoice.totalAmount = 100.0
        
        mockOCRService.mockResult = .success(testInvoice)
        
        let testImage = UIImage(systemName: "doc.text")!
        await viewModel.scanInvoice(image: testImage)
        
        XCTAssertNotNil(viewModel.currentDraftInvoice)
        XCTAssertEqual(viewModel.currentDraftInvoice?.merchantName, "Test Merchant")
        XCTAssertEqual(viewModel.currentDraftInvoice?.totalAmount, 100.0)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isProcessing)
    }
    
    @MainActor
    func testScanInvoice_Error() async {
        mockOCRService.mockResult = .failure(OCRServiceError.invalidImage)
        
        let testImage = UIImage(systemName: "doc.text")!
        await viewModel.scanInvoice(image: testImage)
        
        XCTAssertNil(viewModel.currentDraftInvoice)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isProcessing)
    }
    
    @MainActor
    func testScanInvoice_ParserError() async {
        let parserError = InvoiceParserError.emptyInput
        mockOCRService.mockResult = .failure(parserError)
        
        let testImage = UIImage(systemName: "doc.text")!
        await viewModel.scanInvoice(image: testImage)
        
        XCTAssertNil(viewModel.currentDraftInvoice)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("boş") == true || viewModel.errorMessage?.contains("empty") == true)
    }
    
    // MARK: - saveInvoice Tests
    
    @MainActor
    func testSaveInvoice_NewInvoice() async {
        var testInvoice = Invoice(userId: "test")
        testInvoice.merchantName = "Test Merchant"
        testInvoice.totalAmount = 100.0
        viewModel.currentDraftInvoice = testInvoice
        
        await viewModel.saveInvoice()
        
        XCTAssertEqual(mockRepository.savedInvoices.count, 1)
        XCTAssertNotNil(mockRepository.savedInvoices.first?.id)
        XCTAssertNil(viewModel.currentDraftInvoice) // Form kapatılmalı
        XCTAssertNil(viewModel.errorMessage)
    }
    
    @MainActor
    func testSaveInvoice_UpdateExisting() async {
        var testInvoice = Invoice(userId: "test")
        testInvoice.id = "existing-id"
        testInvoice.merchantName = "Original Merchant"
        testInvoice.totalAmount = 50.0
        
        // Önce kaydet
        mockRepository.savedInvoices.append(testInvoice)
        viewModel.invoices = [testInvoice]
        
        // Sonra güncelle
        var updatedInvoice = testInvoice
        updatedInvoice.merchantName = "Updated Merchant"
        updatedInvoice.totalAmount = 150.0
        viewModel.currentDraftInvoice = updatedInvoice
        
        await viewModel.saveInvoice()
        
        XCTAssertEqual(mockRepository.savedInvoices.count, 1)
        XCTAssertEqual(mockRepository.savedInvoices.first?.merchantName, "Updated Merchant")
        XCTAssertEqual(mockRepository.savedInvoices.first?.totalAmount, 150.0)
        XCTAssertNil(viewModel.currentDraftInvoice)
    }
    
    @MainActor
    func testSaveInvoice_Error() async {
        var testInvoice = Invoice(userId: "test")
        viewModel.currentDraftInvoice = testInvoice
        
        mockRepository.mockError = NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        
        await viewModel.saveInvoice()
        
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Test error") == true)
    }
    
    @MainActor
    func testSaveInvoice_NoDraftInvoice() async {
        viewModel.currentDraftInvoice = nil
        
        await viewModel.saveInvoice()
        
        // Hiçbir şey olmamalı
        XCTAssertEqual(mockRepository.savedInvoices.count, 0)
    }
    
    // MARK: - editInvoice Tests
    
    func testEditInvoice() {
        var testInvoice = Invoice(userId: "test")
        testInvoice.id = "test-id"
        testInvoice.merchantName = "Test Merchant"
        testInvoice.status = .approved
        
        viewModel.editInvoice(testInvoice)
        
        XCTAssertNotNil(viewModel.currentDraftInvoice)
        XCTAssertEqual(viewModel.currentDraftInvoice?.id, "test-id")
        XCTAssertEqual(viewModel.currentDraftInvoice?.merchantName, "Test Merchant")
        XCTAssertEqual(viewModel.currentDraftInvoice?.status, .edited)
    }
    
    // MARK: - Training Data Tests
    
    @MainActor
    func testSaveInvoice_WithTrainingData() async {
        var originalInvoice = Invoice(userId: "test")
        originalInvoice.merchantName = "Original"
        originalInvoice.totalAmount = 100.0
        
        var correctedInvoice = originalInvoice
        correctedInvoice.merchantName = "Corrected"
        correctedInvoice.totalAmount = 150.0
        
        viewModel.originalOCRInvoice = originalInvoice
        viewModel.currentDraftInvoice = correctedInvoice
        
        await viewModel.saveInvoice()
        
        // Training data kaydedilmeli (mock repository'de kontrol edilemez ama hata olmamalı)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(mockRepository.savedInvoices.count, 1)
    }
}

