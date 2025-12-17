import Foundation
import CoreGraphics

/// Gelişmiş Konumsal Analiz Motoru
/// Apple Vision Framework'ün koordinat verilerini kullanarak faturayı bölgelere ayırır
/// ve veriyi geometrik olarak doğru şekilde çıkarır.
class SpatialEngine {
    
    // MARK: - Zone Definitions
    
    /// Fatura bölgeleri (normalized coordinates 0-1)
    enum InvoiceZone {
        case headerLeft      // Zone A: Y < 0.30, X < 0.50 (Sol Üst - Satıcı Bilgileri)
        case headerRight     // Zone B: Y < 0.30, X >= 0.50 (Sağ Üst - Fatura No, Tarih, ETTN)
        case body            // Zone C: 0.30 <= Y <= 0.70 (Merkez - Tablo/Ürünler)
        case footer          // Zone D: Y > 0.70 (Alt - Toplam Tutar, KDV, Matrah)
        
        /// Bir TextBlock'un hangi bölgede olduğunu belirler
        static func zone(for block: TextBlock) -> InvoiceZone {
            let y = block.frame.midY
            let x = block.frame.midX
            
            if y < 0.30 {
                return x < 0.50 ? .headerLeft : .headerRight
            } else if y <= 0.70 {
                return .body
            } else {
                return .footer
            }
        }
        
        /// Bir TextLine'un hangi bölgede olduğunu belirler
        static func zone(for line: TextLine) -> InvoiceZone {
            let y = line.frame.midY
            let x = line.frame.midX
            
            if y < 0.30 {
                return x < 0.50 ? .headerLeft : .headerRight
            } else if y <= 0.70 {
                return .body
            } else {
                return .footer
            }
        }
    }
    
    // MARK: - Column Detection
    
    /// Sütun pozisyonlarını tespit eder (K-means clustering benzeri)
    /// - Parameter lines: Analiz edilecek satırlar
    /// - Returns: X koordinatlarına göre sütun merkezleri (normalized 0-1)
    static func detectColumns(in lines: [TextLine]) -> [CGFloat] {
        guard !lines.isEmpty else { return [] }
        
        // Tüm blokların X koordinatlarını topla
        var xPositions: [CGFloat] = []
        for line in lines {
            for block in line.blocks {
                xPositions.append(block.frame.midX)
            }
        }
        
        guard !xPositions.isEmpty else { return [] }
        
        // X koordinatlarını sırala
        xPositions.sort()
        
        // Basit clustering: Yakın X değerlerini grupla
        var columns: [CGFloat] = []
        var currentCluster: [CGFloat] = []
        let clusterThreshold: CGFloat = 0.05 // %5 tolerans
        
        for x in xPositions {
            if let lastX = currentCluster.last {
                if abs(x - lastX) < clusterThreshold {
                    currentCluster.append(x)
                } else {
                    // Yeni cluster başlat
                    if !currentCluster.isEmpty {
                        let clusterCenter = currentCluster.reduce(0, +) / CGFloat(currentCluster.count)
                        columns.append(clusterCenter)
                    }
                    currentCluster = [x]
                }
            } else {
                currentCluster = [x]
            }
        }
        
        // Son cluster'ı ekle
        if !currentCluster.isEmpty {
            let clusterCenter = currentCluster.reduce(0, +) / CGFloat(currentCluster.count)
            columns.append(clusterCenter)
        }
        
        // Sütunları sırala (soldan sağa)
        columns.sort()
        
        return columns
    }
    
    /// Bir bloğun hangi sütuna ait olduğunu belirler
    /// - Parameters:
    ///   - block: Analiz edilecek blok
    ///   - columns: Tespit edilmiş sütun merkezleri
    /// - Returns: En yakın sütun index'i (nil ise sütun dışı)
    static func columnIndex(for block: TextBlock, columns: [CGFloat]) -> Int? {
        guard !columns.isEmpty else { return nil }
        
        let blockX = block.frame.midX
        var minDistance: CGFloat = .infinity
        var closestIndex: Int?
        
        for (index, columnX) in columns.enumerated() {
            let distance = abs(blockX - columnX)
            if distance < minDistance {
                minDistance = distance
                closestIndex = index
            }
        }
        
        // Eğer en yakın sütun çok uzaksa, sütun dışı kabul et
        let threshold: CGFloat = 0.10 // %10 tolerans
        if minDistance > threshold {
            return nil
        }
        
        return closestIndex
    }
    
    // MARK: - Zone-based Filtering
    
    /// Belirli bir bölgedeki blokları filtreler
    static func blocks(in zone: InvoiceZone, from blocks: [TextBlock]) -> [TextBlock] {
        return blocks.filter { InvoiceZone.zone(for: $0) == zone }
    }
    
    /// Belirli bir bölgedeki satırları filtreler
    static func lines(in zone: InvoiceZone, from lines: [TextLine]) -> [TextLine] {
        return lines.filter { InvoiceZone.zone(for: $0) == zone }
    }
    
    // MARK: - Advanced Row Clustering
    
    /// Gelişmiş satır gruplama algoritması
    /// - Parameter blocks: Gruplanacak bloklar
    /// - Returns: Gruplanmış satırlar
    static func clusterRows(_ blocks: [TextBlock]) -> [TextLine] {
        guard !blocks.isEmpty else { return [] }
        
        // Blokları Y konumuna göre sırala (yukarıdan aşağıya)
        let sortedBlocks = blocks.sorted { $0.y < $1.y }
        
        var lines: [TextLine] = []
        var currentLineBlocks: [TextBlock] = []
        
        // Dinamik tolerans: Ortalama yüksekliğin %30'u
        let avgHeight = blocks.map { $0.height }.reduce(0, +) / CGFloat(blocks.count)
        let tolerance = max(0.01, avgHeight * 0.3)
        
        for block in sortedBlocks {
            if let lastBlock = currentLineBlocks.last {
                let yDiff = abs(block.midY - lastBlock.midY)
                
                // Aynı satırda mı kontrol et
                if yDiff < tolerance {
                    currentLineBlocks.append(block)
                } else {
                    // Yeni satıra geç
                    if !currentLineBlocks.isEmpty {
                        lines.append(TextLine(blocks: currentLineBlocks))
                    }
                    currentLineBlocks = [block]
                }
            } else {
                currentLineBlocks = [block]
            }
        }
        
        // Son satırı ekle
        if !currentLineBlocks.isEmpty {
            lines.append(TextLine(blocks: currentLineBlocks))
        }
        
        return lines
    }
    
    // MARK: - Self-Healing Logic
    
    /// Matematiksel sağlama ile eksik verileri tamamlar
    /// Kural: Matrah + KDV = Genel Toplam (±1 TL tolerans)
    struct FinancialValidation {
        var totalAmount: Double
        var taxAmount: Double
        var subTotal: Double
        
        /// Eksik verileri matematiksel olarak tamamlar
        mutating func heal() {
            // Senaryo 1: Toplam ve Matrah var, KDV eksik
            if totalAmount > 0 && subTotal > 0 && taxAmount == 0 {
                taxAmount = totalAmount - subTotal
                print("🔧 Self-Healing: KDV hesaplandı = \(taxAmount)")
            }
            
            // Senaryo 2: Toplam ve KDV var, Matrah eksik
            if totalAmount > 0 && taxAmount > 0 && subTotal == 0 {
                subTotal = totalAmount - taxAmount
                print("🔧 Self-Healing: Matrah hesaplandı = \(subTotal)")
            }
            
            // Senaryo 3: Matrah ve KDV var, Toplam eksik
            if subTotal > 0 && taxAmount > 0 && totalAmount == 0 {
                totalAmount = subTotal + taxAmount
                print("🔧 Self-Healing: Toplam hesaplandı = \(totalAmount)")
            }
            
            // Senaryo 4: Sadece Toplam var, Matrah ve KDV eksik
            if totalAmount > 0 && subTotal == 0 && taxAmount == 0 {
                // Varsayılan %18 KDV ile hesapla
                subTotal = totalAmount / 1.18
                taxAmount = totalAmount - subTotal
                print("🔧 Self-Healing: Matrah ve KDV varsayılan %18 ile hesaplandı")
            }
            
            // Senaryo 5: Tutarsızlık kontrolü ve düzeltme
            if totalAmount > 0 && subTotal > 0 && taxAmount > 0 {
                let calculatedTotal = subTotal + taxAmount
                let difference = abs(calculatedTotal - totalAmount)
                
                // Eğer fark 1 TL'den fazlaysa, düzelt
                if difference > 1.0 {
                    // En güvenilir olanı koru, diğerlerini düzelt
                    // Genelde Toplam en güvenilir olur
                    let expectedTax = totalAmount - subTotal
                    if abs(expectedTax - taxAmount) < abs(calculatedTotal - totalAmount) {
                        taxAmount = expectedTax
                        print("🔧 Self-Healing: KDV düzeltildi = \(taxAmount)")
                    } else {
                        subTotal = totalAmount - taxAmount
                        print("🔧 Self-Healing: Matrah düzeltildi = \(subTotal)")
                    }
                }
            }
        }
        
        /// Tutarların matematiksel olarak tutarlı olup olmadığını kontrol eder
        func isValid() -> Bool {
            if totalAmount == 0 { return false }
            if subTotal == 0 && taxAmount == 0 { return false }
            
            let calculatedTotal = subTotal + taxAmount
            let difference = abs(calculatedTotal - totalAmount)
            
            // ±1 TL tolerans
            return difference <= 1.0
        }
    }
}


