import Foundation
import SwiftUI
import Combine
import FirebaseFirestore

/// Fatura süreçlerini (Tarama, Kaydetme, Listeleme) yöneten ViewModel.
/// MVVM mimarisinin merkezidir.
class InvoiceViewModel: ObservableObject {
    
    @Published var invoices: [Invoice] = [] // Kayıtlı faturalar
    @Published var currentDraftInvoice: Invoice? // Şu an düzenlenen fatura
    @Published var isProcessing: Bool = false // Yükleniyor animasyonu için
    @Published var errorMessage: String?
    
    // Servisler
    private let ocrService = OCRService()
    private let db = Firestore.firestore()
    
    /// Görüntüden fatura okuma sürecini başlatır
    func scanInvoice(image: UIImage) {
        self.isProcessing = true
        self.errorMessage = nil
        
        // OCR Servisini çağır
        ocrService.recognizeText(from: image) { [weak self] draftInvoice in
            DispatchQueue.main.async {
                self?.isProcessing = false
                
                if let invoice = draftInvoice {
                    // Parser'dan gelen veriyi taslak olarak ata
                    self?.currentDraftInvoice = invoice
                } else {
                    self?.errorMessage = "Fatura okunamadı. Lütfen tekrar deneyin."
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
            // 1. Önce Firebase'e ekle ve referansı (ref) al
            let ref = try db.collection("invoices").addDocument(from: invoice)
            
            // 2. Firebase'in oluşturduğu ID'yi bizim modele ata
            invoice.id = ref.documentID
            
            // 3. Artık ID'si olan faturayı listeye ekle
            // (Böylece "ID nil" hatası almazsın)
            DispatchQueue.main.async {
                self.invoices.insert(invoice, at: 0)
                self.currentDraftInvoice = nil // Formu kapat
                print("✅ Fatura başarıyla kaydedildi. ID: \(ref.documentID)")
            }
            
        } catch {
            self.errorMessage = "Kaydetme hatası: \(error.localizedDescription)"
            print("❌ Kayıt hatası: \(error.localizedDescription)")
        }
    }
}
