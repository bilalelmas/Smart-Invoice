import SwiftUI

struct InvoiceRowView: View {
    let invoice: Invoice
    var onEdit: (() -> Void)? = nil
    
    var body: some View {
        Button(action: {
            onEdit?()
        }) {
            HStack(spacing: 16) {
            // Sol Taraf: Kategori İkonu (Yuvarlak Arka Planlı)
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "doc.text.fill") // İleride kategoriye göre değişebilir
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
            }
            
            // Orta Kısım: Firma ve Tarih
            VStack(alignment: .leading, spacing: 4) {
                Text(invoice.merchantName.isEmpty ? "Bilinmeyen Satıcı" : invoice.merchantName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(invoice.invoiceDate, style: .date)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Sağ Taraf: Tutar ve Durum
            VStack(alignment: .trailing, spacing: 4) {
                Text("-\(invoice.totalAmount, specifier: "%.2f") ₺") // Gider olduğu için eksi
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary) // Veya .red yapılabilir
                
                // Durum Rozeti
                Text(invoice.status.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(invoice.status).opacity(0.15))
                    .foregroundColor(statusColor(invoice.status))
                    .cornerRadius(6)
            }
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 16) // Kenarlardan boşluk
        }
        .buttonStyle(PlainButtonStyle()) // Tıklanabilir ama stil olmadan
    }
    
    // Duruma göre renk belirleme
    func statusColor(_ status: InvoiceStatus) -> Color {
        switch status {
        case .approved: return .green
        case .pending: return .orange
        case .edited: return .blue
        }
    }
}
