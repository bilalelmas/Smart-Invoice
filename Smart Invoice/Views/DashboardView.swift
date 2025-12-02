import SwiftUI

struct DashboardView: View {
    @StateObject var viewModel = InvoiceViewModel()
    @State private var showScanner = false
    @State private var showEditView = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Liste (Henüz boşsa uyarı göster)
                if viewModel.invoices.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("Henüz fatura eklenmedi.\nKamera butonuna basarak başla.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(viewModel.invoices) { invoice in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(invoice.merchantName.isEmpty ? "Bilinmeyen Satıcı" : invoice.merchantName)
                                    .font(.headline)
                                Text(invoice.invoiceDate, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Text("\(invoice.totalAmount, specifier: "%.2f") ₺")
                                .bold()
                        }
                    }
                }
                
                // Yükleniyor Göstergesi
                if viewModel.isProcessing {
                    Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                    VStack {
                        ProgressView("Fatura Analiz Ediliyor...")
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                    }
                }
            }
            .navigationTitle("Faturalarım")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showScanner = true }) {
                        Image(systemName: "camera.fill")
                        Text("Tara")
                    }
                }
            }
            // Kamera Sayfası Açılınca
            .sheet(isPresented: $showScanner) {
                ScannerView(didFinishScanning: { result in
                    showScanner = false
                    switch result {
                    case .success(let images):
                        if let firstImage = images.first {
                            // Resmi yakaladık, analizi başlat
                            viewModel.scanInvoice(image: firstImage)
                        }
                    case .failure(let error):
                        print("Tarama hatası: \(error.localizedDescription)")
                    }
                }, didCancelScanning: {
                    showScanner = false
                })
            }
            // Analiz bitince otomatik açılan Edit Sayfası
            .sheet(item: $viewModel.currentDraftInvoice) { _ in
                // currentDraftInvoice nil olmadığı sürece burası açılır
                // Binding ile EditView'a bağlıyoruz
                if let _ = viewModel.currentDraftInvoice {
                    InvoiceEditView(
                        invoice: Binding(
                            get: { viewModel.currentDraftInvoice! },
                            set: { viewModel.currentDraftInvoice = $0 }
                        ),
                        onSave: {
                            viewModel.saveInvoice()
                        },
                        onCancel: {
                            viewModel.currentDraftInvoice = nil
                        }
                    )
                }
            }
        }
    }
}
