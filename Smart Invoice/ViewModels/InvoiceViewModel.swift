import Foundation
import SwiftUI
import Combine
import FirebaseFirestore

/// Fatura süreçlerini (Tarama, Kaydetme, Listeleme) yöneten ViewModel.
/// MVVM mimarisinin merkezidir.
class InvoiceViewModel: ObservableObject {
    
    @Published var invoices: [Invoice] = [] // Kayıtlı faturalar
    @Published var currentDraftInvoice: Invoice? // Şu an düzenlenen fatura
    @Published var originalOCRInvoice: Invoice? // Karşılaştırma için orijinal OCR çıktısı
    @Published var currentImage: UIImage? // OCR yapılan görsel (Debug için)
    @Published var isProcessing: Bool = false // Yükleniyor animasyonu için
    @Published var errorMessage: String?
    
    // Servisler
    private let ocrService = OCRService()
    private let db = Firestore.firestore()
    
    /// Görüntüden fatura okuma sürecini başlatır
    func scanInvoice(image: UIImage) {
        self.isProcessing = true
        self.errorMessage = nil
        self.currentImage = image // Görseli sakla
        
        // OCR Servisini çağır
        ocrService.recognizeText(from: image) { [weak self] result in
            DispatchQueue.main.async {
                self?.isProcessing = false
                
                switch result {
                case .success(let invoice):
                    // Parser'dan gelen veriyi taslak olarak ata
                    self?.currentDraftInvoice = invoice
                    self?.originalOCRInvoice = invoice // Orijinal hali sakla (Active Learning için)
                    self?.errorMessage = nil
                case .failure(let error):
                    // Kullanıcıya anlamlı hata mesajı göster
                    if let ocrError = error as? OCRServiceError {
                        self?.errorMessage = ocrError.errorDescription
                    } else if let parserError = error as? InvoiceParserError {
                        self?.errorMessage = parserError.errorDescription
                    } else {
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    
    /// Düzenlenmiş faturayı Firebase'e kaydeder
    func saveInvoice() {
        guard var invoice = currentDraftInvoice else { return }
        
        // Durumu güncelle
        invoice.status = .approved
        invoice.createdAt = Date()
        
        do {
            // Eğer fatura zaten kayıtlıysa (ID varsa), güncelle
            if let invoiceId = invoice.id {
                // Mevcut faturayı güncelle
                try db.collection("invoices").document(invoiceId).setData(from: invoice)
                
                // Listede de güncelle
                if let index = invoices.firstIndex(where: { $0.id == invoiceId }) {
                    DispatchQueue.main.async {
                        self.invoices[index] = invoice
                        self.currentDraftInvoice = nil
                        self.currentImage = nil
                        self.originalOCRInvoice = nil
                        print("✅ Fatura başarıyla güncellendi. ID: \(invoiceId)")
                    }
                }
            } else {
                // Yeni fatura ekle
                let ref = try db.collection("invoices").addDocument(from: invoice)
                invoice.id = ref.documentID
                
                // 3. Active Learning: Değişiklik varsa eğitim verisi olarak kaydet
                if let original = originalOCRInvoice {
                    let diffs = TrainingData.detectDiffs(original: original, final: invoice)
                    if !diffs.isEmpty {
                        let trainingData = TrainingData(
                            invoiceId: ref.documentID,
                            originalOCR: original,
                            userCorrected: invoice,
                            diffs: diffs
                        )
                        try? db.collection("training_data").addDocument(from: trainingData)
                        print("🧠 Eğitim verisi kaydedildi. Değişen alanlar: \(diffs)")
                    }
                }
                
                // 4. Artık ID'si olan faturayı listeye ekle
                DispatchQueue.main.async {
                    self.invoices.insert(invoice, at: 0)
                    self.currentDraftInvoice = nil // Formu kapat
                    self.currentImage = nil // Görseli temizle
                    self.originalOCRInvoice = nil
                    print("✅ Fatura başarıyla kaydedildi. ID: \(ref.documentID)")
                }
            }
            
        } catch {
            self.errorMessage = "Kaydetme hatası: \(error.localizedDescription)"
            print("❌ Kayıt hatası: \(error.localizedDescription)")
        }
    }
    
    /// Kaydedilmiş bir faturayı düzenlemek için açar
    func editInvoice(_ invoice: Invoice) {
        var editableInvoice = invoice
        editableInvoice.status = .edited
        self.currentDraftInvoice = editableInvoice
        self.originalOCRInvoice = nil // Düzenleme için orijinal OCR yok
        self.currentImage = nil // Kaydedilmiş faturalarda görsel yok
    }
}
