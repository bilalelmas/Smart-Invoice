import SwiftUI

struct InvoiceRowView: View {
    let invoice: Invoice
    
    var body: some View {
        HStack {
            // Sol Taraf: İkon ve Firma Adı
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "building.2.crop.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 24))
                    
                    Text(invoice.merchantName.isEmpty ? "Bilinmeyen Satıcı" : invoice.merchantName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                }
                
                Text(invoice.invoiceDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Sağ Taraf: Tutar ve Durum
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(invoice.totalAmount, specifier: "%.2f") ₺")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                
                // Durum Rozeti (Badge)
                Text(invoice.status.rawValue)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(invoice.status).opacity(0.2))
                    .foregroundColor(statusColor(invoice.status))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
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
