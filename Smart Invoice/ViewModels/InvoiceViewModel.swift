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
        ocrService.recognizeText(from: image) { [weak self] draftInvoice in
            DispatchQueue.main.async {
                self?.isProcessing = false
                
                if let invoice = draftInvoice {
                    // Parser'dan gelen veriyi taslak olarak ata
                    self?.currentDraftInvoice = invoice
                    self?.originalOCRInvoice = invoice // Orijinal hali sakla (Active Learning için)
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
            
        } catch {
            self.errorMessage = "Kaydetme hatası: \(error.localizedDescription)"
            print("❌ Kayıt hatası: \(error.localizedDescription)")
        }
    }
}
