import SwiftUI

struct InvoiceEditView: View {
    @Binding var invoice: Invoice
    var onSave: () -> Void
    var onCancel: () -> Void
    
    // Para birimi formatlayıcı
    private let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "TRY"
        return formatter
    }()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // 1. Güven Skoru Kartı
                        confidenceCard
                        
                        // 2. Satıcı Bilgileri
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "SATICI BİLGİLERİ", icon: "building.2.fill")
                            
                            CustomTextField(title: "Firma Adı", text: $invoice.merchantName)
                            CustomTextField(title: "Vergi No", text: $invoice.merchantTaxID, keyboardType: .numberPad)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                        
                        // 3. Fatura Detayları
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "FATURA DETAYLARI", icon: "doc.text.fill")
                            
                            CustomTextField(title: "Fatura No", text: $invoice.invoiceNo)
                            
                            HStack {
                                Text("Fatura Tarihi")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Spacer()
                                DatePicker("", selection: $invoice.invoiceDate, displayedComponents: .date)
                                    .labelsHidden()
                            }
                            .padding(.vertical, 4)
                            
                            CustomTextField(title: "ETTN", text: $invoice.ettn)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                        
                        // 4. Finansal Bilgiler
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "FİNANSAL VERİLER", icon: "turkishlirasign.circle.fill")
                            
                            HStack {
                                Text("Toplam Tutar")
                                    .font(.headline)
                                Spacer()
                                TextField("0.00", value: $invoice.totalAmount, formatter: currencyFormatter)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.title3.bold())
                                    .foregroundColor(.blue)
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("KDV")
                                    .font(.subheadline)
                                Spacer()
                                TextField("0.00", value: $invoice.taxAmount, formatter: currencyFormatter)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                        
                        // Kaydet Butonu
                        Button(action: onSave) {
                            Text("Değişiklikleri Onayla ve Kaydet")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(16)
                                .shadow(radius: 5)
                        }
                        .padding(.top, 10)
                        
                        Spacer(minLength: 50)
                    }
                    .padding()
                }
            }
            .navigationTitle("Fatura Doğrulama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { onCancel() }
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    var confidenceCard: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("AI Güven Skoru")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Yapay zeka bu faturayı %\(Int(invoice.confidenceScore * 100)) oranında doğru okuduğunu düşünüyor.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 6)
                    .frame(width: 50, height: 50)
                
                Circle()
                    .trim(from: 0, to: CGFloat(invoice.confidenceScore))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))
                
                Text("%\(Int(invoice.confidenceScore * 100))")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(
            LinearGradient(gradient: Gradient(colors: [invoice.confidenceScore > 0.7 ? Color.green : Color.orange, Color.blue]), startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(16)
        .shadow(radius: 5)
    }
}

// MARK: - Helper Components

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.gray)
        }
    }
}

struct CustomTextField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)
            
            TextField("", text: $text)
                .padding(10)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(8)
                .keyboardType(keyboardType)
        }
    }
}
