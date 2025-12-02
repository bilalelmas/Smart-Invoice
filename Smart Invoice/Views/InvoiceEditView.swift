import SwiftUI

/// OCR sonrası kullanıcının verileri doğruladığı ve düzelttiği ekran.
struct InvoiceEditView: View {
    
    @Binding var invoice: Invoice // ViewModel'deki veriye bağlı (Binding)
    var onSave: () -> Void
    var onCancel: () -> Void
    
    // Para birimi formatlayıcı
    private let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "TRY" // Veya "TL"
        return formatter
    }()
    
    var body: some View {
        NavigationView {
            Form {
                // Bölüm 1: Fatura Temel Bilgileri
                Section(header: Text("Fatura Bilgileri")) {
                    TextField("Fatura No", text: $invoice.invoiceNo)
                        .keyboardType(.namePhonePad)
                    
                    DatePicker("Tarih", selection: $invoice.invoiceDate, displayedComponents: .date)
                    
                    TextField("ETTN (Senaryo)", text: $invoice.ettn)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                // Bölüm 2: Satıcı Bilgileri
                Section(header: Text("Satıcı Bilgileri")) {
                    TextField("Firma Adı", text: $invoice.merchantName)
                    TextField("Vergi No", text: $invoice.merchantTaxID)
                        .keyboardType(.numberPad)
                }
                
                // Bölüm 3: Tutarlar
                Section(header: Text("Finansal Veriler")) {
                    HStack {
                        Text("Toplam Tutar")
                        Spacer()
                        TextField("0.00", value: $invoice.totalAmount, formatter: currencyFormatter)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("KDV")
                        Spacer()
                        TextField("0.00", value: $invoice.taxAmount, formatter: currencyFormatter)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                // Bölüm 4: Analiz Bilgisi (Tez sunumu için güzel detay)
                Section(header: Text("Sistem Analizi"), footer: Text("Bu skor, yapay zekanın okuma kalitesini gösterir.")) {
                    HStack {
                        Text("OCR Güven Skoru")
                        Spacer()
                        Text(String(format: "%%.0f", invoice.confidenceScore * 100))
                            .foregroundColor(invoice.confidenceScore > 0.7 ? .green : .red)
                            .bold()
                    }
                }
            }
            .navigationTitle("Fatura Doğrulama")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { onSave() }
                }
            }
        }
    }
}
