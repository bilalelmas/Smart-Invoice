import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @StateObject var viewModel = InvoiceViewModel()
    
    // UI Durumları
    @State private var showScanner = false
    @State private var showImagePicker = false
    @State private var showFilePicker = false
    @State private var selectedImage: UIImage?
    @State private var fileData: Data? // Dosya picker için
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground) // Hafif gri arka plan
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // ÜST ÖZET KARTI
                    summaryHeader
                    
                    // LİSTE ALANI
                    if viewModel.invoices.isEmpty {
                        emptyStateView
                    } else {
                        List {
                            ForEach(viewModel.invoices) { invoice in
                                InvoiceRowView(invoice: invoice)
                                    .listRowSeparator(.hidden) // Çizgileri kaldır
                                    .listRowBackground(Color.clear) // Arka planı temizle
                                    .padding(.bottom, 6)
                            }
                            .onDelete(perform: deleteInvoice)
                        }
                        .listStyle(.plain)
                        .refreshable {
                            // İleride buraya Firebase'den veri çekme gelecek
                        }
                    }
                }
                
                // YÜKLENİYOR
                if viewModel.isProcessing {
                    loadingOverlay
                }
            }
            .navigationTitle("Cüzdan")
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
                DocumentPicker(content: $fileData, isPresented: $showFilePicker) { url in
                    // PDF ise resme çevir, resimse direkt al
                    if url.pathExtension.lowercased() == "pdf" {
                        if let pdfImage = PDFHelper.pdfToImage(url: url) {
                            viewModel.scanInvoice(image: pdfImage)
                        }
                    } else {
                        // Resim dosyası ise
                        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
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
    
    // MARK: - UI Bileşenleri
    
    var summaryHeader: some View {
        VStack(alignment: .leading) {
            Text("Bu Ay Toplam")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            
            // Toplam tutarı hesapla
            let total = viewModel.invoices.reduce(0) { $0 + $1.totalAmount }
            Text("\(total, specifier: "%.2f") ₺")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]), startPoint: .topLeading, endPoint: .bottomTrailing))
        .cornerRadius(16)
        .padding()
        .shadow(radius: 5)
    }
    
    var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            Text("Henüz fatura yok")
                .font(.headline)
                .foregroundColor(.gray)
            Text("Sağ üstteki (+) butonuna basarak\nfatura ekleyebilirsin.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray.opacity(0.8))
            Spacer()
        }
    }
    
    var menuButton: some View {
        Menu {
            Button(action: { showScanner = true }) {
                Label("Kamera ile Tara", systemImage: "camera")
            }
            Button(action: { showImagePicker = true }) {
                Label("Galeriden Seç", systemImage: "photo")
            }
            Button(action: { showFilePicker = true }) {
                Label("Dosyalardan Yükle (PDF)", systemImage: "folder")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 30))
                .foregroundColor(.blue)
        }
    }
    
    var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
            VStack(spacing: 15) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Analiz Ediliyor...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(Color.gray.opacity(0.8)) // Blur efekti yerine basit gri
            .cornerRadius(20)
        }
    }
    
    // MARK: - Fonksiyonlar
    
    func deleteInvoice(at offsets: IndexSet) {
        viewModel.invoices.remove(atOffsets: offsets)
        // Firebase silme işlemi buraya eklenecek
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
