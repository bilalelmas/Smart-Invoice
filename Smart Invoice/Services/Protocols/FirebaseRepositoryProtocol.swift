import Foundation
import FirebaseFirestore

/// Firebase işlemleri için protocol
/// Dependency Injection ve test edilebilirlik için
protocol FirebaseInvoiceRepositoryProtocol {
    /// Yeni fatura ekle
    /// - Parameter invoice: Eklenecek fatura
    /// - Returns: Oluşturulan document ID
    /// - Throws: Firestore hataları
    func addInvoice(_ invoice: Invoice) async throws -> String
    
    /// Mevcut faturayı güncelle
    /// - Parameter invoice: Güncellenecek fatura (ID içermeli)
    /// - Throws: Firestore hataları
    func updateInvoice(_ invoice: Invoice) async throws
    
    /// Faturayı sil
    /// - Parameter invoiceId: Silinecek fatura ID'si
    /// - Throws: Firestore hataları
    func deleteInvoice(_ invoiceId: String) async throws
    
    /// Tüm faturaları getir
    /// - Returns: Fatura listesi
    /// - Throws: Firestore hataları
    func getAllInvoices() async throws -> [Invoice]
    
    /// Training data ekle
    /// - Parameter trainingData: Eğitim verisi
    /// - Throws: Firestore hataları
    func addTrainingData(_ trainingData: TrainingData) async throws
    
    /// ETTN numarası ile fatura ara
    /// - Parameter ettn: ETTN numarası
    /// - Returns: Bulunan fatura (varsa), nil (yoksa)
    /// - Throws: Firestore hataları
    func findInvoiceByETTN(_ ettn: String) async throws -> Invoice?
}

