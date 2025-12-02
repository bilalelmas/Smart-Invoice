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
            // 3. Analiz Bitince Düzenleme Ekranı (EditView)
            .sheet(item: $viewModel.currentDraftInvoice) { _ in
                // Sheet içeriğini oluştururken güvenli kontrol
                InvoiceEditView(
                    invoice: Binding(
                        get: { 
                            // KRİTİK DÜZELTME: (!) yerine (??) kullanıyoruz.
                            // Eğer nil ise boş bir fatura objesi döndür ki çökmez.
                            viewModel.currentDraftInvoice ?? Invoice(userId: "") 
                        },
                        set: { newValue in
                            // Değişiklikleri geri yansıt
                            viewModel.currentDraftInvoice = newValue 
                        }
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
    
    // MARK: - Analysis Header
    var analysisHeader: some View {
        VStack(spacing: 16) {
            // Üst Başlık ve Tarih
            HStack {
                VStack(alignment: .leading) {
                    Text("Finansal Özet")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                    Text("Bu Ay")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                Spacer()
                // Belge Sayısı Rozeti
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.fill")
                    Text("\(viewModel.invoices.count) Belge")
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.2))
                .cornerRadius(20)
                .foregroundColor(.white)
            }
            
            // Finansal Detaylar (Grid Yapısı)
            HStack(spacing: 0) {
                // 1. Matrah (Vergisiz)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Matrah")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Text(formatCurrency(calculateTotalBaseAmount()))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Ayraç
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 1, height: 30)
                
                // 2. KDV
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top. KDV")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Text(formatCurrency(calculateTotalTax()))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.orange) // KDV dikkat çeksin
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
            }
            
            Divider().background(Color.white.opacity(0.3))
            
            // 3. Genel Toplam (En Altta Büyük)
            HStack {
                Text("Genel Toplam")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text(formatCurrency(calculateTotalAmount()))
                    .font(.system(size: 28, weight: .bold)) // Daha büyük
                    .foregroundColor(.white)
            }
        }
        .padding(20)
        .background(
            LinearGradient(gradient: Gradient(colors: [Color(hex: "1a2a6c"), Color(hex: "b21f1f")]), startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
    
    // Yardımcı Hesaplamalar
    func calculateTotalAmount() -> Double {
        viewModel.invoices.reduce(0) { $0 + $1.totalAmount }
    }
    
    func calculateTotalTax() -> Double {
        viewModel.invoices.reduce(0) { $0 + $1.taxAmount }
    }
    
    func calculateTotalBaseAmount() -> Double {
        calculateTotalAmount() - calculateTotalTax()
    }
    
    func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: NSNumber(value: value)) ?? "₺0,00"
    }
    
    // MARK: - UI Bileşenleri
    
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
