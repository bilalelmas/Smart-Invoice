import Foundation
import FirebaseFirestore

/// Fatura durumunu takip etmek için enum
enum InvoiceStatus: String, Codable, CaseIterable {
    case pending = "Onay Bekliyor" // OCR yapıldı, kullanıcı onayı bekleniyor
    case approved = "Onaylandı"    // Firebase'e kaydedildi
    case edited = "Düzenlendi"     // Kullanıcı tarafından değiştirildi
}

/// Fatura içindeki ürün kalemlerini temsil eden model
/// Python projesindeki 'kalem_eslestirme_map' yapısına uygun tasarlandı.
struct InvoiceItem: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String      // Ürün/Hizmet Adı
    var quantity: Double  // Miktar
    var unitPrice: Double // Birim Fiyat
    var total: Double     // Satır Toplamı (KDV hariç veya dahil)
    var taxRate: Int      // KDV Oranı (%)
    
    // UI'da boş bir satır oluşturmak için
    static var empty: InvoiceItem {
        return InvoiceItem(name: "", quantity: 1, unitPrice: 0, total: 0, taxRate: 18)
    }
}

/// Ana Fatura Modeli
struct Invoice: Identifiable, Codable {
    // Firebase Document ID'si
    @DocumentID var id: String?
    
    // Meta Veriler
    var userId: String
    var status: InvoiceStatus = .pending
    var createdAt: Date = Date()
    
    // Python projesinden aldığımız alanlar (alan_eslestirme_map)
    var merchantName: String = ""       // satici_firma_unvani
    var merchantTaxID: String = ""      // satici_vergi_numarasi
    var merchantAddress: String = ""    // satici_adres
    
    var invoiceNo: String = ""          // fatura_numarasi
    var invoiceDate: Date = Date()      // fatura_tarihi
    var ettn: String = ""               // ettn (Evrensel Tekil Tanımlama Numarası)
    
    // Finansal Veriler
    var totalAmount: Double = 0.0       // genel_toplam
    var taxAmount: Double = 0.0         // hesaplanan_kdv
    var subTotal: Double = 0.0          // vergi_haric_tutar
    
    // Ürün Kalemleri (Opsiyonel - İleri seviye hedef)
    var items: [InvoiceItem] = []
    
    // OCR Güven Skoru (Analiz kalitesini ölçmek için)
    var confidenceScore: Float = 0.0
    
    /// Python projesindeki CSV çıktısına benzer bir string formatı döndürür (Export için)
    func toCSVString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        let dateStr = formatter.string(from: invoiceDate)
        
        return "\(invoiceNo),\(dateStr),\(merchantName),\(totalAmount),\(status.rawValue)"
    }
    
    // Helper init for parsing where userId might not be known yet
    init(userId: String = "") {
        self.userId = userId
    }
    
    // Debug / Görselleştirme Verileri (Firestore'a kaydedilmez)
    var debugRegions: [OCRRegion] = []
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case status
        case createdAt
        case merchantName
        case merchantTaxID
        case merchantAddress
        case invoiceNo
        case invoiceDate
        case ettn
        case totalAmount
        case taxAmount
        case subTotal
        case items
        case confidenceScore
        // debugRegions hariç tutuldu
    }
}

/// Görsel Hata Ayıklama için Bölge Modeli
struct OCRRegion: Identifiable, Codable {
    var id: String = UUID().uuidString
    var type: RegionType
    var rect: CGRect // Normalleştirilmiş (0-1)
    
    enum RegionType: String, Codable {
        case seller = "Satıcı Bloğu" // Kırmızı
        case total = "Toplam Tutar"  // Yeşil
        case subTotal = "Ara Toplam" // Turuncu
        case tax = "KDV"             // Mor
        case table = "Tablo Alanı"   // Mavi
        case date = "Tarih"          // Sarı
    }
}
