import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: InvoiceViewModel
    @State private var csvUrl: URL?
    @State private var pdfUrl: URL?
    
    // Şirket Bilgileri (Şimdilik sabit, ileride UserDefaults'tan çekilebilir)
    @State private var companyName = "Şirketim A.Ş."
    @State private var taxNumber = "1234567890"
    @State private var taxOffice = "Maslak V.D."
    
    var body: some View {
        NavigationStack {
            List {
                // 1. Şirket Profili
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "building.2.crop.circle.fill")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundColor(Color(hex: "4e54c8"))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(companyName)
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Vergi No: \(taxNumber)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(taxOffice)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Şirket Bilgileri")
                }
                
                // 2. İstatistikler
                Section {
                    HStack {
                        Text("Toplam Fatura")
                        Spacer()
                        Text("\(viewModel.invoices.count)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Kayıtlı Yıl")
                        Spacer()
                        Text("2024") // Dinamik yapılabilir
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Genel Durum")
                }
                
                // 3. Veri Yönetimi
                Section {
                    if let csvUrl = csvUrl {
                        ShareLink(item: csvUrl) {
                            HStack {
                                Image(systemName: "tablecells")
                                    .foregroundColor(.green)
                                Text("Excel (CSV) Olarak Paylaş")
                                    .foregroundColor(.primary)
                            }
                        }
                    } else {
                        ProgressView("Rapor Hazırlanıyor...")
                    }
                    
                    if let pdfUrl = pdfUrl {
                        ShareLink(item: pdfUrl) {
                            HStack {
                                Image(systemName: "doc.richtext")
                                    .foregroundColor(.red)
                                Text("PDF Tablosu Olarak Paylaş")
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                } header: {
                    Text("Veri Yönetimi")
                } footer: {
                    Text("Tüm fatura verilerinizi muhasebe programlarına uygun formatta dışa aktarır.")
                }
                
                // 4. Uygulama Ayarları
                Section {
                    NavigationLink(destination: Text("KDV Ayarları (Yakında)")) {
                        HStack {
                            Image(systemName: "percent")
                                .foregroundColor(.orange)
                            Text("KDV Oranları")
                        }
                    }
                    NavigationLink(destination: Text("Tema Ayarları (Yakında)")) {
                        HStack {
                            Image(systemName: "paintbrush")
                                .foregroundColor(.purple)
                            Text("Görünüm")
                        }
                    }
                } header: {
                    Text("Ayarlar")
                }
                
                // 5. Hakkında
                Section {
                    HStack {
                        Text("Sürüm")
                        Spacer()
                        Text("1.0.0 (Beta)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Profil")
            .background(Color(UIColor.systemGroupedBackground))
            .onAppear {
                generateReports()
            }
            .onChange(of: viewModel.invoices.count) {
                generateReports()
            }
        }
    }
    
    func generateReports() {
        // Raporları arka planda oluştur
        DispatchQueue.global(qos: .userInitiated).async {
            let csv = ExportService.shared.generateCSV(from: viewModel.invoices)
            let pdf = ExportService.shared.generatePDF(from: viewModel.invoices)
            
            DispatchQueue.main.async {
                self.csvUrl = csv
                self.pdfUrl = pdf
            }
        }
    }
}
