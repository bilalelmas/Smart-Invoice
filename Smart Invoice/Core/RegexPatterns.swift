import Foundation

/// Fatura analizi için kullanılan tüm Regex desenlerini ve anahtar kelimeleri içeren merkezi yapı.
/// Mühendislik Notu: "Separation of Concerns" ilkesi gereği, veri desenleri ile iş mantığı ayrıştırılmıştır.
struct RegexPatterns {
    
    // MARK: - Regex Cache
    /// Performans için regex pattern'lerini cache'ler
    private static var regexCache: [String: NSRegularExpression] = [:]
    private static let cacheQueue = DispatchQueue(label: "com.smartinvoice.regexcache", attributes: .concurrent)
    
    /// Pattern'i cache'den al veya oluştur ve cache'le
    static func getRegex(pattern: String, options: NSRegularExpression.Options = .caseInsensitive) -> NSRegularExpression? {
        return cacheQueue.sync {
            if let cached = regexCache[pattern] {
                return cached
            }
            
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                regexCache[pattern] = regex
                return regex
            }
            
            return nil
        }
    }
    
    // MARK: - 1. Sayısal Desenler
    struct Amount {
        /// Standart Para: 1.250,50 veya 100,00
        static let standard = "[0-9]+[.,][0-9]{2}"
        
        /// İyileştirilmiş Esnek Para: Daha spesifik, yıl ve telefon numarası gibi false positive'leri önler
        /// Örnek: 1.250,50 TL, 195 TL, 100,00
        /// Word boundary kullanarak yıl (2024) gibi değerleri hariç tutar
        static let flexible = "\\b\\d{1,3}(?:\\.\\d{3})*(?:[.,]\\d{1,2})?\\s*(?:TL|₺)?\\b"
    }
    
    // MARK: - 2. Tarih Desenleri
    struct DateFormat {
        /// Standart Tarih: dd.mm.yyyy, dd/mm/yyyy, dd-mm-yyyy
        /// 1900'ler ve 2000'ler desteği
        static let standard = "\\b(0[1-9]|[12][0-9]|3[01])[-./](0[1-9]|1[012])[-./](19|20)\\d{2}\\b"
    }
    
    // MARK: - 3. Kimlik Desenleri
    struct ID {
        /// VKN (Vergi Kimlik No): 10 hane
        static let vkn = "\\b[0-9]{10}\\b"
        
        /// TCKN (TC Kimlik No): 11 hane
        static let tckn = "\\b[0-9]{11}\\b"
        
        /// ETTN (UUID): Standart UUID formatı
        /// OCR hatalarını (l/1, O/0) post-processing'de düzeltilecek
        static let ettn = "[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}"
    }
    
    // MARK: - 4. Fatura No Desenleri
    struct InvoiceNo {
        /// Standart e-Arşiv: 3 Harf + Yıl + 9 Rakam (ABC2023123456789)
        static let standard = "[A-Z0-9]{3}20[0-9]{2}[0-9]{9}"
        
        /// Kısa Format: 3 Harf + 13 Rakam (Eski tip veya özel entegratör)
        static let short = "\\b[A-Z]{3}[0-9]{13}\\b"
        
        /// A101 Özel: 'A' harfi ile başlayan 15 hane
        static let a101 = "\\bA[0-9]{15}\\b"
        
        /// Junglee/Trendyol Pazaryeri Özel: FA veya TYF ile başlayan
        static let marketplace = "\\b(FA|TYF)[0-9]{14}\\b"
    }
    
    // MARK: - 5. Anahtar Kelime Sözlüğü (Keywords)
    struct Keywords {
        /// Faturayı "Satıcı" ve "Alıcı" olarak ikiye bölen kelimeler
        static let splitters = ["SAYIN", "ALICI", "MÜŞTERİ", "TESLİMAT ADRESİ"]
        
        /// Tutar Tespiti için "Ödenecek Tutar" (En Alt Satır) Anahtar Kelimeleri
        static let payableAmounts = ["ÖDENECEK", "GENEL TOPLAM", "VERGİLER DAHİL", "TOPLAM TUTAR"]
        
        /// Ara Toplam (Matrah) Anahtar Kelimeleri
        static let subTotalAmounts = ["MAL HİZMET", "TOPLAM İSKONTO", "KDV MATRAHI", "ARA TOPLAM", "TOPLAM TUTAR (KDV HARİÇ)", "KDV HARİÇ"]
        
        /// Tutar Tespiti için Kara Liste (Bunları Toplam sanma!)
        static let amountBlacklist = ["HARIÇ", "HARIC", "MATRAH", "NET", "KDV'SİZ", "KDVSİZ", "İSKONTO", "ISKONTO"]
        
        /// KDV (Vergi) Tutarını Bulmak İçin Anahtar Kelimeler
        static let taxAmounts = ["HESAPLANAN KDV", "TOPLAM KDV", "KDV TUTARI", "HESAPLANAN KATMA DEĞER VERGİSİ", "KDV (%18)", "KDV (%20)", "KDV (%10)"]
        
        /// Tarih Etiketleri
        static let dateTargets = ["FATURA TARİHİ", "DÜZENLEME TARİHİ", "DÜZENLEME ZAMANI"]
        static let dateBlacklist = ["SİPARİŞ", "SIPARIS", "ÖDEME", "VADE", "TESLİMAT"]
        
        /// Firma Adı Tespiti için Şirket Ekleri
        static let companySuffixes = ["A.Ş", "A.S", "LTD", "LIMITED", "LİMİTED", "TİC", "TIC", "SAN", "ANONİM", "ŞTİ", "ŞİRKETİ", "MAĞAZACILIK"]
        
        /// Firma Adı için Kara Liste (Bu kelimeler varsa firma adı değildir)
        static let merchantBlacklist = ["BELGE NO", "SİPARİŞ", "TARİH", "IRSALIYE", "SAYFA", "FATURA", "MÜŞTERİ", "VKN:", "VERGİ", "WEB", "ADRES"]
        
        /// Tablo Başlıkları (Ürünleri bulmak için)
        static let tableHeaders = ["MAL HİZMET", "ÜRÜN ADI", "CİNSİ", "AÇIKLAMA", "MALIN CİNSİ"]
        
        /// Tablo Bitiş İşaretleri
        static let tableFooters = ["TOPLAM", "ÖDENECEK", "YALNIZ", "GENEL TOPLAM", "ARA TOPLAM"]
    }
}
