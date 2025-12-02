import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @StateObject var viewModel = InvoiceViewModel()
    
    // UI Durumları
    @State private var showScanner = false
    @State private var showImagePicker = false
    @State private var showFilePicker = false
    @State private var showActionSheet = false
    @State private var selectedImage: UIImage?
    @State private var fileData: Data?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // ÜST ANALİZ KARTI
                    analysisHeader
                    
                    // LİSTE ALANI
                    if viewModel.invoices.isEmpty {
                        emptyStateView
                    } else {
                        List {
                            // Faturaları tarihe göre grupla
                            ForEach(groupedInvoices.keys.sorted(by: >), id: \.self) { date in
                                Section(header: Text(dateFormatter.string(from: date))) {
                                    ForEach(groupedInvoices[date] ?? []) { invoice in
                                        InvoiceRowView(invoice: invoice)
                                            .listRowSeparator(.hidden)
                                            .listRowBackground(Color.clear)
                                            .padding(.bottom, 6)
                                    }
                                    .onDelete(perform: deleteInvoice)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            // Firebase refresh logic
                        }
                    }
                }
                
                // YÜKLENİYOR
                if viewModel.isProcessing {
                    loadingOverlay
                }
            }
            .navigationTitle("Fatura Analiz")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    menuButton
                }
            }
            // --- MODALLAR ---
            .sheet(isPresented: $showScanner) {
                ScannerView(didFinishScanning: handleScan, didCancelScanning: { showScanner = false })
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImage: $selectedImage, isPresented: $showImagePicker)
                    .onDisappear { if let img = selectedImage { viewModel.scanInvoice(image: img); selectedImage = nil } }
            }
            .sheet(isPresented: $showFilePicker) {
                // DocumentPicker artık sadece onSelect ile URL dönüyor
                DocumentPicker { localUrl in
                    print("📁 Dosya seçildi: \(localUrl.path)")
                    
                    // Dosya seçildikten sonra sheet'i kapat
                    showFilePicker = false
                    
                    // Uzantıya göre işlem yap
                    let extensionName = localUrl.pathExtension.lowercased()
                    
                    if extensionName == "pdf" {
                        // PDF Helper ile resme çevir
                        if let pdfImage = PDFHelper.pdfToImage(url: localUrl) {
                            print("✅ PDF Resme çevrildi, analize gönderiliyor...")
                            viewModel.scanInvoice(image: pdfImage)
                        } else {
                            print("❌ PDF Resme çevrilemedi.")
                        }
                    } else if ["jpg", "jpeg", "png"].contains(extensionName) {
                        // Resim dosyası ise
                        if let data = try? Data(contentsOf: localUrl), let img = UIImage(data: data) {
                            print("✅ Resim yüklendi, analize gönderiliyor...")
                            viewModel.scanInvoice(image: img)
                        }
                    }
                }
            }
            .sheet(item: $viewModel.currentDraftInvoice) { _ in
                if let _ = viewModel.currentDraftInvoice {
                    InvoiceEditView(
                        invoice: Binding(get: { viewModel.currentDraftInvoice! }, set: { viewModel.currentDraftInvoice = $0 }),
                        onSave: { viewModel.saveInvoice() },
                        onCancel: { viewModel.currentDraftInvoice = nil }
                    )
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    // Faturaları tarihe göre gruplama (Sadece gün bazlı)
    var groupedInvoices: [Date: [Invoice]] {
        Dictionary(grouping: viewModel.invoices) { invoice in
            Calendar.current.startOfDay(for: invoice.invoiceDate)
        }
    }
    
    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter
    }
    
    // MARK: - UI Bileşenleri
    
    var analysisHeader: some View {
        HStack(spacing: 20) {
            // Sol: Toplam Tutar
            VStack(alignment: .leading) {
                Text("Toplam Gider")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                
                let total = viewModel.invoices.reduce(0) { $0 + $1.totalAmount }
                Text("\(total, specifier: "%.2f") ₺")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Sağ: Fatura Sayısı
            VStack(alignment: .trailing) {
                Text("İşlenen Belge")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                
                Text("\(viewModel.invoices.count)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(Color.blue) // Daha kurumsal, düz renk
        .cornerRadius(12)
        .padding()
        .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
    }
    
    var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            Text("Analiz Bekleyen Veri Yok")
                .font(.headline)
                .foregroundColor(.gray)
            Text("Fatura ekleyerek harcama analizlerinizi\nburada görebilirsiniz.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray.opacity(0.8))
            Spacer()
        }
    }
    
    var menuButton: some View {
        Button(action: { showActionSheet = true }) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(8)
                .background(Circle().fill(Color.blue))
        }
        .confirmationDialog("Fatura Ekle", isPresented: $showActionSheet, titleVisibility: .visible) {
            Button("Kamera ile Tara") { showScanner = true }
            Button("Galeriden Seç") { showImagePicker = true }
            Button("Dosyalardan Yükle (PDF)") { showFilePicker = true }
            Button("İptal", role: .cancel) { }
        }
    }
    
    var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
            VStack(spacing: 15) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Veriler Analiz Ediliyor...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(Color.gray.opacity(0.8))
            .cornerRadius(20)
        }
    }
    
    // MARK: - Fonksiyonlar
    
    func deleteInvoice(at offsets: IndexSet) {
        // Gruplu listeden silme işlemi biraz daha karmaşık olabilir
        // Basitlik için şimdilik ViewModel'den direkt silmeyi desteklemiyoruz
        // İleride eklenebilir.
    }
    
    func handleScan(result: Result<[UIImage], Error>) {
        showScanner = false
        switch result {
        case .success(let images):
            if let firstImage = images.first {
                viewModel.scanInvoice(image: firstImage)
            }
        case .failure(let error):
            print(error.localizedDescription)
        }
    }
}
