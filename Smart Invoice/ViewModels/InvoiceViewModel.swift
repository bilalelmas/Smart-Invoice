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
    
    // Filtreleme ve Arama
    @Published var searchText: String = ""
    @Published var selectedVendor: String? = nil
    @Published var selectedStatus: InvoiceStatus? = nil
    @Published var dateRange: ClosedRange<Date>? = nil
    @Published var amountRange: ClosedRange<Double>? = nil
    
    // Raporlama
    @Published var csvUrl: URL?
    @Published var pdfUrl: URL?
    
    // Servisler (Dependency Injection)
    private let ocrService: OCRServiceProtocol
    private let invoiceParser: InvoiceParserProtocol
    private let repository: FirebaseInvoiceRepositoryProtocol
    
    // Constructor Injection
    init(
        ocrService: OCRServiceProtocol = OCRService(),
        invoiceParser: InvoiceParserProtocol = InvoiceParser.shared,
        repository: FirebaseInvoiceRepositoryProtocol = FirebaseInvoiceRepository()
    ) {
        self.ocrService = ocrService
        self.invoiceParser = invoiceParser
        self.repository = repository
    }
    
    /// Firebase'den tüm faturaları yükler
    @MainActor
    func loadInvoices() async {
        self.isProcessing = true
        self.errorMessage = nil
        
        do {
            let loadedInvoices = try await repository.getAllInvoices()
            self.invoices = loadedInvoices
            print("✅ \(loadedInvoices.count) fatura yüklendi")
        } catch {
            self.errorMessage = "Faturalar yüklenirken hata oluştu: \(error.localizedDescription)"
            print("❌ Fatura yükleme hatası: \(error.localizedDescription)")
        }
        
        self.isProcessing = false
    }
    
    /// Görüntüden fatura okuma sürecini başlatır.
    /// - Parameter image: Taranacak fatura görüntüsü.
    @MainActor
    func scanInvoice(image: UIImage) async {
        self.isProcessing = true
        self.errorMessage = nil
        self.currentImage = image // Görseli sakla
        
        do {
            // OCR Servisini çağır
            let invoice = try await ocrService.recognizeText(from: image)
            
            // Parser'dan gelen veriyi taslak olarak ata
            // Sheet çakışmasını önlemek için kısa bir gecikme ekle
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 saniye
            
            self.currentDraftInvoice = invoice
            self.originalOCRInvoice = invoice // Orijinal hali sakla (Active Learning için)
            self.errorMessage = nil
            self.isProcessing = false
        } catch {
            self.isProcessing = false
            
            // Kullanıcıya anlamlı hata mesajı göster
            if let ocrError = error as? OCRServiceError {
                self.errorMessage = ocrError.errorDescription
            } else if let parserError = error as? InvoiceParserError {
                self.errorMessage = parserError.errorDescription
            } else {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    /// Düzenlenmiş faturayı Firebase'e kaydeder.
    /// Yeni fatura ise ekler, mevcutsa günceller.
    @MainActor
    func saveInvoice() async {
        guard var invoice = currentDraftInvoice else { return }
        
        // Durumu güncelle
        invoice.status = .approved
        invoice.createdAt = Date()
        
        do {
            // Eğer fatura zaten kayıtlıysa (ID varsa), güncelle
            if let invoiceId = invoice.id {
                // Mevcut faturayı güncelle
                try await repository.updateInvoice(invoice)
                
                // Listede de güncelle
                if let index = invoices.firstIndex(where: { $0.id == invoiceId }) {
                    self.invoices[index] = invoice
                    self.currentDraftInvoice = nil
                    self.currentImage = nil
                    self.originalOCRInvoice = nil
                    print("✅ Fatura başarıyla güncellendi. ID: \(invoiceId)")
                }
            } else {
                // Yeni fatura eklemeden önce ETTN ile duplicate kontrolü yap
                if !invoice.ettn.isEmpty {
                    if let existingInvoice = try await repository.findInvoiceByETTN(invoice.ettn) {
                        // Aynı ETTN'ye sahip fatura bulundu
                        if let existingId = existingInvoice.id {
                            // Mevcut faturayı güncelle
                            invoice.id = existingId
                            try await repository.updateInvoice(invoice)
                            
                            // Listede de güncelle
                            if let index = invoices.firstIndex(where: { $0.id == existingId }) {
                                self.invoices[index] = invoice
                            } else {
                                // Eğer listede yoksa ekle (yeniden yükleme gerekebilir)
                                self.invoices.insert(invoice, at: 0)
                            }
                            
                            self.currentDraftInvoice = nil
                            self.currentImage = nil
                            self.originalOCRInvoice = nil
                            print("✅ Aynı ETTN'ye sahip fatura bulundu, güncellendi. ID: \(existingId)")
                            return
                        }
                    }
                }
                
                // Yeni fatura ekle (ETTN yoksa veya duplicate yoksa)
                let invoiceId = try await repository.addInvoice(invoice)
                invoice.id = invoiceId
                
                // 3. Active Learning: Değişiklik varsa eğitim verisi olarak kaydet
                if let original = originalOCRInvoice {
                    let diffs = TrainingData.detectDiffs(original: original, final: invoice)
                    if !diffs.isEmpty {
                        let trainingData = TrainingData(
                            invoiceId: invoiceId,
                            originalOCR: original,
                            userCorrected: invoice,
                            diffs: diffs
                        )
                        do {
                            try await repository.addTrainingData(trainingData)
                            print("🧠 Eğitim verisi kaydedildi. Değişen alanlar: \(diffs)")
                        } catch {
                            print("⚠️ Eğitim verisi kaydedilemedi: \(error.localizedDescription)")
                            // Ana akışı bozmamak için hatayı yutuyoruz ama logluyoruz
                        }
                    }
                }
                
                // 4. Artık ID'si olan faturayı listeye ekle
                self.invoices.insert(invoice, at: 0)
                self.currentDraftInvoice = nil // Formu kapat
                self.currentImage = nil // Görseli temizle
                self.originalOCRInvoice = nil
                print("✅ Fatura başarıyla kaydedildi. ID: \(invoiceId)")
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
    
    /// Bir faturayı Firebase'den ve yerel listeden siler.
    @MainActor
    func deleteInvoice(_ invoice: Invoice) async {
        guard let invoiceId = invoice.id else { return }
        do {
            try await repository.deleteInvoice(invoiceId)
            self.invoices.removeAll { $0.id == invoiceId }
        } catch {
            self.errorMessage = "Silme hatası: \(error.localizedDescription)"
            print("❌ Silme hatası: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Raporlama
    
    /// Faturalar için PDF ve CSV raporlarını oluşturur.
    /// Sonuçlar `csvUrl` ve `pdfUrl` değişkenlerine atanır.
    @MainActor
    func generateReports() async {
        let invoicesToExport = self.invoices
        do {
            // Background thread'de çalıştır
            let (csv, pdf) = try await Task.detached(priority: .userInitiated) {
                let csv = try await ExportService.shared.generateCSV(from: invoicesToExport)
                let pdf = try await ExportService.shared.generatePDF(from: invoicesToExport)
                return (csv, pdf)
            }.value
            
            self.csvUrl = csv
            self.pdfUrl = pdf
        } catch {
            self.errorMessage = "Rapor oluşturma hatası: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Filtreleme ve Arama
    
    /// Mevcut filtrelere göre filtrelenmiş fatura listesini döndürür.
    var filteredInvoices: [Invoice] {
        var result = invoices
        
        // Metin araması (satıcı, fatura no, ETTN)
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            result = result.filter { invoice in
                let merchantMatch = invoice.merchantName.lowercased().contains(searchLower)
                let numberMatch = invoice.invoiceNo.lowercased().contains(searchLower)
                let ettnMatch = invoice.ettn.lowercased().contains(searchLower)
                return merchantMatch || numberMatch || ettnMatch
            }
        }
        
        // Satıcı filtresi
        if let vendor = selectedVendor, !vendor.isEmpty {
            result = result.filter { $0.merchantName == vendor }
        }
        
        // Durum filtresi
        if let status = selectedStatus {
            result = result.filter { $0.status == status }
        }
        
        // Tarih aralığı filtresi
        if let dateRange = dateRange {
            result = result.filter { dateRange.contains($0.invoiceDate) }
        }
        
        // Tutar aralığı filtresi
        if let amountRange = amountRange {
            result = result.filter { amountRange.contains($0.totalAmount) }
        }
        
        return result
    }
    
    /// Tüm benzersiz satıcı isimlerini döndürür
    var uniqueVendors: [String] {
        Array(Set(invoices.map { $0.merchantName })).sorted()
    }
    
    /// Filtreleri temizler
    func clearFilters() {
        searchText = ""
        selectedVendor = nil
        selectedStatus = nil
        dateRange = nil
        amountRange = nil
    }
    
    /// Filtrelerin aktif olup olmadığını kontrol eder
    var hasActiveFilters: Bool {
        !searchText.isEmpty || selectedVendor != nil || selectedStatus != nil || dateRange != nil || amountRange != nil
    }
}
