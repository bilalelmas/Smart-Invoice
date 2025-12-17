import Foundation
import FirebaseFirestore

/// Firebase işlemlerini yöneten repository implementasyonu
class FirebaseInvoiceRepository: FirebaseInvoiceRepositoryProtocol {
    private let db = Firestore.firestore()
    
    func addInvoice(_ invoice: Invoice) async throws -> String {
        let ref = try db.collection("invoices").addDocument(from: invoice)
        return ref.documentID
    }
    
    func updateInvoice(_ invoice: Invoice) async throws {
        guard let invoiceId = invoice.id else {
            throw NSError(domain: "FirebaseInvoiceRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invoice ID is required for update"])
        }
        try db.collection("invoices").document(invoiceId).setData(from: invoice)
    }
    
    func deleteInvoice(_ invoiceId: String) async throws {
        try await db.collection("invoices").document(invoiceId).delete()
    }
    
    func getAllInvoices() async throws -> [Invoice] {
        let snapshot = try await db.collection("invoices")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return try snapshot.documents.compactMap { document in
            try document.data(as: Invoice.self)
        }
    }
    
    func addTrainingData(_ trainingData: TrainingData) async throws {
        _ = try db.collection("training_data").addDocument(from: trainingData)
    }
    
    func findInvoiceByETTN(_ ettn: String) async throws -> Invoice? {
        guard !ettn.isEmpty else { return nil }
        
        let snapshot = try await db.collection("invoices")
            .whereField("ettn", isEqualTo: ettn)
            .limit(to: 1)
            .getDocuments()
        
        guard let document = snapshot.documents.first else {
            return nil
        }
        
        do {
            return try document.data(as: Invoice.self)
        } catch {
            print("❌ Invoice decode hatası: \(error.localizedDescription)")
            return nil
        }
    }
}

