import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .home
    @StateObject private var viewModel = InvoiceViewModel()
    
    // Tab Bar'ı gizlemek için
    @State private var isTabBarHidden = false
    
    // Global State (Eskiden DashboardView'daydı)
    @State private var showActionSheet = false
    @State private var showScanner = false
    @State private var showImagePicker = false
    @State private var showFilePicker = false
    @State private var selectedImage: UIImage?
    
    enum Tab: String {
        case home
        case scan
        case analytics
        case profile
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Ana İçerik
            Group {
                switch selectedTab {
                case .home:
                    DashboardView(viewModel: viewModel)
                case .scan:
                    Color.clear // Buraya düşmez
                case .analytics:
                    AnalyticsView(viewModel: viewModel)
                case .profile:
                    Text("Profil Ekranı (Yakında)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(hex: "F2F2F7"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Global Loading Overlay
            if viewModel.isProcessing {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Fiş Analiz Ediliyor...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(30)
                .background(Material.ultraThinMaterial)
                .cornerRadius(20)
            }
            
            // Custom Tab Bar
            if !isTabBarHidden {
                CustomTabBar(selectedTab: $selectedTab) {
                    showActionSheet = true
                }
                .padding(.bottom, 20)
            }
        }
        .ignoresSafeArea(.keyboard)
        // MARK: - Global Sheets
        .confirmationDialog("Fatura Ekle", isPresented: $showActionSheet, titleVisibility: .visible) {
            Button("Kamera ile Tara") { showScanner = true }
            Button("Galeriden Seç") { showImagePicker = true }
            Button("Dosyalardan Yükle (PDF)") { showFilePicker = true }
            Button("İptal", role: .cancel) { }
        }
        .sheet(isPresented: $showScanner) {
            ScannerView(didFinishScanning: { result in
                showScanner = false
                // Sheet kapanma animasyonu için gecikme
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    switch result {
                    case .success(let images):
                        if let firstImage = images.first {
                            viewModel.scanInvoice(image: firstImage)
                        }
                    case .failure(let error):
                        print("Tarama hatası: \(error.localizedDescription)")
                    }
                }
            }, didCancelScanning: {
                showScanner = false
            })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage, isPresented: $showImagePicker)
                .onDisappear {
                    if let img = selectedImage {
                        // Sheet kapanma animasyonu için gecikme
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            viewModel.scanInvoice(image: img)
                            selectedImage = nil
                        }
                    }
                }
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker { localUrl in
                showFilePicker = false
                // Sheet kapanma animasyonu için gecikme
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let extensionName = localUrl.pathExtension.lowercased()
                    if extensionName == "pdf" {
                        if let pdfImage = PDFHelper.pdfToImage(url: localUrl) {
                            viewModel.scanInvoice(image: pdfImage)
                        }
                    } else if ["jpg", "jpeg", "png"].contains(extensionName) {
                        if let data = try? Data(contentsOf: localUrl), let img = UIImage(data: data) {
                            viewModel.scanInvoice(image: img)
                        }
                    }
                }
            }
        }
        // Düzenleme Ekranı (Global)
        .sheet(item: $viewModel.currentDraftInvoice) { _ in
            InvoiceEditView(
                invoice: Binding(
                    get: { viewModel.currentDraftInvoice ?? Invoice(userId: "") },
                    set: { viewModel.currentDraftInvoice = $0 }
                ),
                onSave: { viewModel.saveInvoice() },
                onCancel: { viewModel.currentDraftInvoice = nil }
            )
        }
    }
}

// MARK: - Custom Tab Bar Tasarımı
struct CustomTabBar: View {
    @Binding var selectedTab: MainTabView.Tab
    var onScanTapped: () -> Void
    
    var body: some View {
        HStack {
            // Sol Taraf
            Spacer()
            TabBarButton(icon: "house.fill", tab: .home, selectedTab: $selectedTab)
            Spacer()
            
            // Orta: Scan Butonu (Dışa Taşan)
            Button(action: onScanTapped) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(gradient: Gradient(colors: [Color(hex: "4e54c8"), Color(hex: "8f94fb")]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)
                        .shadow(color: Color(hex: "4e54c8").opacity(0.4), radius: 10, x: 0, y: 5)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .offset(y: -24) // Yukarı taşıma efekti
            
            Spacer()
            
            // Sağ Taraf
            TabBarButton(icon: "chart.bar.xaxis", tab: .analytics, selectedTab: $selectedTab)
            Spacer()
            TabBarButton(icon: "person.fill", tab: .profile, selectedTab: $selectedTab)
            Spacer()
        }
        .frame(height: 70)
        .background(
            Color.white
                .cornerRadius(35)
                .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal, 24)
    }
}

struct TabBarButton: View {
    let icon: String
    let tab: MainTabView.Tab
    @Binding var selectedTab: MainTabView.Tab
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(selectedTab == tab ? Color(hex: "4e54c8") : Color.gray.opacity(0.5))
                    .scaleEffect(selectedTab == tab ? 1.1 : 1.0)
                
                // Seçili nokta göstergesi
                if selectedTab == tab {
                    Circle()
                        .fill(Color(hex: "4e54c8"))
                        .frame(width: 4, height: 4)
                } else {
                    Circle().fill(Color.clear).frame(width: 4, height: 4)
                }
            }
        }
    }
}
