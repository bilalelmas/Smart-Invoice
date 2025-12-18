import SwiftUI

/// Uygulamanın ana shell’i: tez-core kullanıcı akışı için sadece 3 sekme içerir:
/// 1) Faturalar (Dashboard)  2) Değerlendirme (Evaluation)  3) Profil / Export.
struct MainTabView: View {
    @State private var selectedTab: Tab = .home
    @StateObject private var viewModel = DIContainer.shared.makeInvoiceViewModel()
    @State private var isTabBarHidden = false
    
    // Global State (fatura ekleme akışı)
    @State private var showActionSheet = false
    @State private var showScanner = false
    @State private var showImagePicker = false
    @State private var showFilePicker = false
    @State private var selectedImage: UIImage?
    @State private var showErrorAlert = false
    
    enum Tab: String {
        /// Kayıtlı faturaların listelendiği ve filtrelendiği ana ekran.
        case home
        /// Golden dataset / pipeline doğruluk testleri için değerlendirme ekranı.
        case evaluation
        /// Profil, veri export ve gelişmiş (isteğe bağlı) ayarların olduğu ekran.
        case profile
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(viewModel: viewModel)
                .tabItem {
                    Label("Faturalar", systemImage: "doc.text.magnifyingglass")
                }
                .tag(Tab.home)
            
            EvaluationView()
                .tabItem {
                    Label("Değerlendirme", systemImage: "checklist")
                }
                .tag(Tab.evaluation)
            
            ProfileView(viewModel: viewModel)
                .tabItem {
                    Label("Profil", systemImage: "person.fill")
                }
                .tag(Tab.profile)
        }
        .alert("Hata", isPresented: $showErrorAlert) {
            Button("Tamam") {
                viewModel.errorMessage = nil
                showErrorAlert = false
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            showErrorAlert = newValue != nil
        }
        .ignoresSafeArea(.keyboard)
        
        // --- Fatura ekleme aksiyonu (kameradan, galeriden veya dosyadan) ---
        .confirmationDialog("Fatura Ekle", isPresented: $showActionSheet, titleVisibility: .visible) {
            Button("Kamera ile Tara") { showScanner = true }
            Button("Galeriden Seç") { showImagePicker = true }
            Button("Dosyalardan Yükle (PDF)") { showFilePicker = true }
            Button("İptal", role: .cancel) { }
        }
        .sheet(isPresented: $showScanner) {
            ScannerView(
                didFinishScanning: { result in
                    showScanner = false
                    Task { @MainActor in
                        do { try await Task.sleep(nanoseconds: 500_000_000) } catch {}
                        if case .success(let images) = result, let img = images.first {
                            await viewModel.scanInvoice(image: img)
                        }
                    }
                },
                didCancelScanning: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage, isPresented: $showImagePicker)
                .onDisappear {
                    if let img = selectedImage {
                        Task { @MainActor in
                            do { try await Task.sleep(nanoseconds: 500_000_000) } catch {}
                            await viewModel.scanInvoice(image: img)
                            selectedImage = nil
                        }
                    }
                }
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker { localUrl in
                showFilePicker = false
                Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: 500_000_000) } catch {}
                    
                    // PDF seçimi
                    if localUrl.pathExtension.lowercased() == "pdf" {
                        let canAccess = localUrl.startAccessingSecurityScopedResource()
                        defer { if canAccess { localUrl.stopAccessingSecurityScopedResource() } }
                        
                        if let pdfImg = PDFHelper.pdfToImage(url: localUrl) {
                            await viewModel.scanInvoice(image: pdfImg)
                        } else {
                            viewModel.errorMessage = "PDF dosyası işlenemedi. Lütfen geçerli bir PDF seçin."
                        }
                    } else {
                        // Görsel seçimi
                        let canAccess = localUrl.startAccessingSecurityScopedResource()
                        defer { if canAccess { localUrl.stopAccessingSecurityScopedResource() } }
                        
                        do {
                            let data = try Data(contentsOf: localUrl)
                            if let img = UIImage(data: data) {
                                await viewModel.scanInvoice(image: img)
                            } else {
                                viewModel.errorMessage = "Resim dosyası yüklenemedi."
                            }
                        } catch {
                            viewModel.errorMessage = "Dosya okunamadı: \(error.localizedDescription)"
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
                onCancel: {
                    viewModel.currentDraftInvoice = nil
                    viewModel.currentImage = nil
                },
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

// MARK: - Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: MainTabView.Tab
    var onScanTapped: () -> Void
    
    var body: some View {
        HStack {
            Spacer()
            TabBarButton(icon: "house.fill", tab: .home, selectedTab: $selectedTab)
            Spacer()
            TabBarButton(icon: "checklist", tab: .evaluation, selectedTab: $selectedTab)
            Spacer()
            Button(action: onScanTapped) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(radius: 10)
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .offset(y: -24)
            Spacer()
            TabBarButton(icon: "person.fill", tab: .profile, selectedTab: $selectedTab)
            Spacer()
        }
        .frame(height: 70)
        .background(
            Color.white
                .cornerRadius(35)
                .shadow(radius: 5)
        )
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


