import SwiftUI

struct InvoiceRowView: View {
    let invoice: Invoice
    var onEdit: (() -> Void)? = nil
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
                onEdit?()
            }
        }) {
            HStack(spacing: 16) {
                // Sol Taraf: Kategori İkonu (Yuvarlak Arka Planlı)
                ZStack {
                    Circle()
                        .fill(iconBackgroundColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: iconForMerchant(invoice.merchantName))
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(iconBackgroundColor)
                }
                
                // Orta Kısım: Firma ve Tarih
                VStack(alignment: .leading, spacing: 6) {
                    Text(invoice.merchantName.isEmpty ? "Bilinmeyen Satıcı" : invoice.merchantName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text(invoice.invoiceDate, style: .date)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        
                        if !invoice.invoiceNo.isEmpty {
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("#\(invoice.invoiceNo)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Sağ Taraf: Tutar ve Durum
                VStack(alignment: .trailing, spacing: 6) {
                    Text(formatCurrency(invoice.totalAmount))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)
                    
                    // Durum Rozeti
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor(invoice.status))
                            .frame(width: 6, height: 6)
                        Text(invoice.status.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor(invoice.status).opacity(0.12))
                    .foregroundColor(statusColor(invoice.status))
                    .cornerRadius(8)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // Duruma göre renk belirleme
    func statusColor(_ status: InvoiceStatus) -> Color {
        switch status {
        case .approved: return .green
        case .pending: return .orange
        case .edited: return .blue
        }
    }
    
    // Satıcıya göre ikon belirleme
    func iconForMerchant(_ merchantName: String) -> String {
        let lowercased = merchantName.lowercased()
        
        if lowercased.contains("trendyol") || lowercased.contains("marketplace") {
            return "cart.fill"
        } else if lowercased.contains("a101") || lowercased.contains("market") {
            return "storefront.fill"
        } else if lowercased.contains("flo") || lowercased.contains("müzik") {
            return "music.note"
        } else if lowercased.contains("restoran") || lowercased.contains("cafe") {
            return "fork.knife"
        } else if lowercased.contains("benzin") || lowercased.contains("petrol") {
            return "fuelpump.fill"
        } else {
            return "doc.text.fill"
        }
    }
    
    // İkon arka plan rengi
    var iconBackgroundColor: Color {
        let lowercased = invoice.merchantName.lowercased()
        
        if lowercased.contains("trendyol") || lowercased.contains("marketplace") {
            return .purple
        } else if lowercased.contains("a101") || lowercased.contains("market") {
            return .red
        } else if lowercased.contains("flo") || lowercased.contains("müzik") {
            return .pink
        } else {
            return .blue
        }
    }
    
    // Para formatı
    func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "₺0,00"
    }
}
