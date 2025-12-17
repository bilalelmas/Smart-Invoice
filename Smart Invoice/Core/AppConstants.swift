import Foundation
import CoreImage
import UIKit

/// Uygulama genelinde tekrar kullanılan pahalı nesnelerin (Thread-Safe) tutulduğu yapı.
/// Bu sınıf Performans Optimizasyonu amacıyla oluşturulmuştur.
/// - Note: CIContext ve DateFormatter gibi nesnelerin tekrar tekrar oluşturulması maliyetlidir.
enum AppConstants {
    
    // MARK: - Core Image Context
    
    /// Paylaşılan CIContext örneği.
    /// OCR ve filtreleme işlemlerinde her defasında yeni context oluşturmamak için kullanılır.
    /// - Important: Thread-safe'dir, ancak GPU kaynaklarını verimli kullanmak için tek instance tercih edilir.
    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // MARK: - Formatters
    
    /// Tarih formatlama işlemleri için paylaşılan formatter.
    /// - Note: DateFormatter thread-safe DEĞİLDİR (Swift < 5.7), ancak yeni Swift versiyonlarında bu durum iyileştirildi.
    /// Güvenlik için her thread'de kopyalanarak veya lock ile kullanılmalıdır veya concurrency safe bir wrapper kullanılabilir.
    /// Bu projede seri kuyruklar veya main actor üzerinde kullanıldığı varsayılarak static tanımlanmıştır.
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()
    
    /// Alternatif tarih formatları için yardımcı fonksiyon
    /// - Parameter format: Date format string (örn: "yyyy-MM-dd")
    /// - Returns: Yapılandırılmış DateFormatter (Cache mekanizması eklenebilir)
    static func dateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = format
        return formatter
    }
    
    /// Para birimi formatlama işlemleri için paylaşılan formatter.
    static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.currencySymbol = "₺"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()
}
