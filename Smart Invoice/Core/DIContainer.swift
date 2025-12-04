import Foundation
import SwiftUI

/// Dependency Injection Container
/// Servisleri merkezi bir yerden yönetir ve ViewModel'lere inject eder
class DIContainer {
    // Singleton instance
    static let shared = DIContainer()
    
    // Servisler
    let ocrService: OCRServiceProtocol
    let invoiceParser: InvoiceParserProtocol
    let repository: FirebaseInvoiceRepositoryProtocol
    
    // Constructor - Production dependencies
    init(
        ocrService: OCRServiceProtocol? = nil,
        invoiceParser: InvoiceParserProtocol? = nil,
        repository: FirebaseInvoiceRepositoryProtocol? = nil
    ) {
        // Default implementasyonlar (production)
        self.ocrService = ocrService ?? OCRService(invoiceParser: InvoiceParser.shared)
        self.invoiceParser = invoiceParser ?? InvoiceParser.shared
        self.repository = repository ?? FirebaseInvoiceRepository()
    }
    
    // Factory method - InvoiceViewModel oluştur
    func makeInvoiceViewModel() -> InvoiceViewModel {
        return InvoiceViewModel(
            ocrService: ocrService,
            invoiceParser: invoiceParser,
            repository: repository
        )
    }
}

