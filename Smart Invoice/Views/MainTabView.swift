import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .home
    @StateObject private var viewModel = DIContainer.shared.makeInvoiceViewModel()
    @State private var isTabBarHidden = false
    
    // Global State
    @State private var showActionSheet = false
    @State private var showScanner = false
    @State private var showImagePicker = false
    @State private var showFilePicker = false
    @State private var selectedImage: UIImage?
    @State private var showErrorAlert = false
    
    enum Tab: String {
        case home, scan, analytics, profile, test
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Ana İçerik
            Group {
                switch selectedTab {
                case .home:
                    DashboardView(viewModel: viewModel)
                case .scan:
                    Color.clear
                case .analytics:
                    AnalyticsView(viewModel: viewModel)
                case .profile:
                    ProfileView(viewModel: viewModel)
                case .test:
                    EvaluationView() // Yeni Test Ekranı
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Loading
            if viewModel.isProcessing {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 20) {
                    ProgressView().scaleEffect(1.5).tint(.white)
                    Text("İşleniyor...").font(.headline).foregroundColor(.white)
                }
                .padding(30)
                .background(Material.ultraThinMaterial)
                .cornerRadius(20)
            }
            
            // Tab Bar
            if !isTabBarHidden {
                CustomTabBar(selectedTab: $selectedTab) { showActionSheet = true }
                    .padding(.bottom, 20)
            }
        }
        .alert("Hata", isPresented: $showErrorAlert) {
            Button("Tamam") {
                viewModel.errorMessage = nil
                showErrorAlert = false
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: viewModel.errorMessage) {
            showErrorAlert = viewModel.errorMessage != nil
        }
        .ignoresSafeArea(.keyboard)
        
        // --- Action Sheets & Modals ---
        .confirmationDialog("Fatura Ekle", isPresented: $showActionSheet, titleVisibility: .visible) {
            Button("Kamera ile Tara") { showScanner = true }
            Button("Galeriden Seç") { showImagePicker = true }
            Button("Dosyalardan Yükle (PDF)") { showFilePicker = true }
            Button("İptal", role: .cancel) { }
        }
        .sheet(isPresented: $showScanner) {
            ScannerView(didFinishScanning: { result in
                showScanner = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 saniye
                    if case .success(let images) = result, let img = images.first {
                        await viewModel.scanInvoice(image: img)
                    }
                }
            }, didCancelScanning: { showScanner = false })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage, isPresented: $showImagePicker)
                .onDisappear {
                    if let img = selectedImage {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 saniye
                            await viewModel.scanInvoice(image: img)
                            selectedImage = nil
                        }
                    }
                }
        }
        .sheet(isPresented: $showFilePicker, onDismiss: {
            // Sheet kapandıktan sonra işlem yapılacak
        }) {
            DocumentPicker { localUrl in
                // Sheet'i kapat
                showFilePicker = false
                
                // Dosya işleme işlemini sheet kapandıktan sonra yap
                Task { @MainActor in
                    // Sheet'in tamamen kapanması için bekle
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 saniye
                    
                    // PDF dosyası kontrolü
                    if localUrl.pathExtension.lowercased() == "pdf" {
                        print("📄 PDF seçildi: \(localUrl.lastPathComponent)")
                        
                        // Security scoped resource erişimi
                        let canAccess = localUrl.startAccessingSecurityScopedResource()
                        defer {
                            if canAccess {
                                localUrl.stopAccessingSecurityScopedResource()
                            }
                        }
                        
                        if let pdfImg = PDFHelper.pdfToImage(url: localUrl) {
                            print("✅ PDF görüntüye dönüştürüldü, boyut: \(pdfImg.size)")
                            await viewModel.scanInvoice(image: pdfImg)
                        } else {
                            print("❌ PDF görüntüye dönüştürülemedi")
                            viewModel.errorMessage = "PDF dosyası işlenemedi. Lütfen geçerli bir PDF dosyası seçin."
                        }
                    } else {
                        // Resim dosyası kontrolü
                        print("🖼️ Resim dosyası seçildi: \(localUrl.lastPathComponent)")
                        
                        let canAccess = localUrl.startAccessingSecurityScopedResource()
                        defer {
                            if canAccess {
                                localUrl.stopAccessingSecurityScopedResource()
                            }
                        }
                        
                        if let data = try? Data(contentsOf: localUrl), let img = UIImage(data: data) {
                            print("✅ Resim yüklendi, boyut: \(img.size)")
                            await viewModel.scanInvoice(image: img)
                        } else {
                            print("❌ Resim yüklenemedi")
                            viewModel.errorMessage = "Resim dosyası yüklenemedi. Lütfen geçerli bir resim dosyası seçin."
                        }
                    }
                }
            }
        }
        .sheet(item: $viewModel.currentDraftInvoice) { _ in
            InvoiceEditView(
                invoice: Binding(
                    get: { viewModel.currentDraftInvoice ?? Invoice(userId: "") },
                    set: { viewModel.currentDraftInvoice = $0 }
                ),
                onSave: {
                    Task { @MainActor in
                        await viewModel.saveInvoice()
                    }
                },
                onCancel: { viewModel.currentDraftInvoice = nil; viewModel.currentImage = nil },
                image: viewModel.currentImage
            )
        }
        .onAppear {
            // Uygulama açıldığında faturaları yükle
            if viewModel.invoices.isEmpty {
                Task {
                    await viewModel.loadInvoices()
                }
            }
        }
    }
}

// ... CustomTabBar ve TabBarButton aynı kalabilir ...
struct CustomTabBar: View {
    @Binding var selectedTab: MainTabView.Tab
    var onScanTapped: () -> Void
    var body: some View {
        HStack {
            Spacer()
            TabBarButton(icon: "house.fill", tab: .home, selectedTab: $selectedTab)
            Spacer()
            TabBarButton(icon: "checklist", tab: .test, selectedTab: $selectedTab) // Test İkonu
            Spacer()
            Button(action: onScanTapped) {
                ZStack {
                    Circle().fill(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)
                        .shadow(radius: 10)
                    Image(systemName: "plus").font(.system(size: 28, weight: .bold)).foregroundColor(.white)
                }
            }.offset(y: -24)
            Spacer()
            TabBarButton(icon: "chart.bar.xaxis", tab: .analytics, selectedTab: $selectedTab)
            Spacer()
            TabBarButton(icon: "person.fill", tab: .profile, selectedTab: $selectedTab)
            Spacer()
        }
        .frame(height: 70)
        .background(Color.white.cornerRadius(35).shadow(radius: 5))
        .padding(.horizontal)
    }
}

struct TabBarButton: View {
    let icon: String
    let tab: MainTabView.Tab
    @Binding var selectedTab: MainTabView.Tab
    var body: some View {
        Button(action: { withAnimation { selectedTab = tab } }) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(selectedTab == tab ? .blue : .gray)
                .scaleEffect(selectedTab == tab ? 1.2 : 1.0)
        }
    }
}
