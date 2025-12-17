import Foundation
import UIKit
import PDFKit

/// Dışa aktarma/Raporlama işlemleri sırasında oluşabilecek hatalar.
enum ExportError: LocalizedError {
    case pdfGenerationFailed
    case csvGenerationFailed
    case fileWriteFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .pdfGenerationFailed: return "PDF dosyası oluşturulamadı."
        case .csvGenerationFailed: return "CSV verisi oluşturulamadı."
        case .fileWriteFailed(let msg): return "Dosya diske yazılamadı: \(msg)"
        }
    }
}

/// Faturaları dışa aktarmak (PDF/CSV) için kullanılan servis.
/// Tüm dışa aktarma işlemleri bu sınıf üzerinden yönetilir.
class ExportService {
    static let shared = ExportService()
    
    private init() {}
    
    /// Faturaları Excel (CSV) formatına çevirir
    /// - Parameter invoices: Dışa aktarılacak fatura listesi
    /// - Returns: Oluşturulan geçici CSV dosyasının URL'i
    /// - Throws: `ExportError` eğer dosya oluşturulamazsa
    func generateCSV(from invoices: [Invoice]) throws -> URL {
        // CSV Başlıkları
        var csvString = "Tarih,Firma Adı,Fatura No,Vergi No,Tutar (TL),KDV (TL),Durum\n"
        
        // Verileri satır satır ekle
        for invoice in invoices {
            let dateStr = formatDate(invoice.invoiceDate)
            // Virgüller CSV'yi bozmasın diye temizliyoruz
            let merchant = cleanCSV(invoice.merchantName)
            let status = invoice.status.rawValue
            
            let line = "\(dateStr),\(merchant),\(invoice.invoiceNo),\(invoice.merchantTaxID),\(invoice.totalAmount),\(invoice.taxAmount),\(status)\n"
            csvString.append(line)
        }
        
        // Geçici bir dosya oluştur
        let fileName = "Harcama_Raporu_\(Int(Date().timeIntervalSince1970)).csv"
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try csvString.write(to: path, atomically: true, encoding: .utf8)
            return path
        } catch {
            print("❌ CSV Hatası: \(error)")
            throw ExportError.fileWriteFailed(error.localizedDescription)
        }
    }
    
    /// Faturaları PDF Tablosuna çevirir (Basit Çizim)
    /// - Parameter invoices: Dışa aktarılacak fatura listesi
    /// - Returns: Oluşturulan geçici PDF dosyasının URL'i
    /// - Throws: `ExportError` eğer PDF oluşturulamazsa
    func generatePDF(from invoices: [Invoice]) throws -> URL {
        let format = UIGraphicsPDFRendererFormat()
        let metaData = [kCGPDFContextTitle: "Fatura Raporu", kCGPDFContextAuthor: "Smart Invoice"]
        format.documentInfo = metaData as [String: Any]
        
        let pageWidth = 8.5 * 72.0 // A4 Genişlik benzeri
        let pageHeight = 11 * 72.0 // A4 Yükseklik benzeri
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        var pdfData: Data?
        
        pdfData = renderer.pdfData { (context) in
            context.beginPage()
            
            // Başlık
            let title = "Harcama Raporu"
            let titleAttrs = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 24)]
            title.draw(at: CGPoint(x: 50, y: 50), withAttributes: titleAttrs)
            
            // Tarih Bilgisi
            let dateInfo = "Oluşturulma: \(formatDate(Date()))"
            dateInfo.draw(at: CGPoint(x: 50, y: 80), withAttributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 12)])
            
            // Tablo Başlıkları (Koordinatları elle ayarlıyoruz)
            let yStart = 120.0
            drawText("TARİH", x: 50, y: yStart, isBold: true)
            drawText("FİRMA", x: 150, y: yStart, isBold: true)
            drawText("FATURA NO", x: 350, y: yStart, isBold: true)
            drawText("TUTAR", x: 500, y: yStart, isBold: true)
            
            var y = yStart + 30
            
            // Satırlar
            for invoice in invoices {
                // Sayfa sonuna geldik mi?
                if y > pageHeight - 50 {
                    context.beginPage()
                    y = 50
                }
                
                drawText(formatDate(invoice.invoiceDate), x: 50, y: y)
                // Firma adı çok uzunsa kes
                let merchant = invoice.merchantName.count > 25 ? String(invoice.merchantName.prefix(25)) + "..." : invoice.merchantName
                drawText(merchant, x: 150, y: y)
                drawText(invoice.invoiceNo, x: 350, y: y)
                drawText(String(format: "%.2f ₺", invoice.totalAmount), x: 500, y: y)
                
                y += 20
            }
            
            // Dip Toplam
            y += 20
            let total = invoices.reduce(0) { $0 + $1.totalAmount }
            drawText("GENEL TOPLAM: \(String(format: "%.2f ₺", total))", x: 400, y: y, isBold: true)
        }
        
        guard let data = pdfData else {
            throw ExportError.pdfGenerationFailed
        }
        
        let fileName = "Harcama_Raporu_\(Int(Date().timeIntervalSince1970)).pdf"
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: path)
            return path
        } catch {
            print("❌ PDF Hatası: \(error)")
            throw ExportError.fileWriteFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        return AppConstants.dateFormatter.string(from: date)
    }
    
    private func cleanCSV(_ text: String) -> String {
        return text.replacingOccurrences(of: ",", with: " ")
    }
    
    private func drawText(_ text: String, x: Double, y: Double, isBold: Bool = false) {
        let font = isBold ? UIFont.boldSystemFont(ofSize: 10) : UIFont.systemFont(ofSize: 10)
        let attrs = [NSAttributedString.Key.font: font]
        text.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }
}
