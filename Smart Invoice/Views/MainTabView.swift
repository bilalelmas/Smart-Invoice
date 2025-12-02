import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .home
    @StateObject private var viewModel = InvoiceViewModel() // ViewModel'i en üstte tutuyoruz
    
    // Tab Bar'ı gizlemek için (Örn: Kamera açılınca)
    @State private var isTabBarHidden = false
    
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
                    // Scan butonu özel olduğu için buraya düşmez ama güvenli olsun
                    Color.clear
                case .analytics:
                    Text("Analiz Ekranı (Yakında)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(hex: "F2F2F7"))
                case .profile:
                    Text("Profil Ekranı (Yakında)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(hex: "F2F2F7"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Custom Tab Bar
            if !isTabBarHidden {
                CustomTabBar(selectedTab: $selectedTab) {
                    // Scan butonuna basılınca ne olacak?
                    // Şimdilik DashboardView içindeki mantığı buraya taşıyacağız
                    // Faz 2'de burayı detaylandıracağız.
                    print("Scan Tapped")
                }
                .padding(.bottom, 20)
            }
        }
        .ignoresSafeArea(.keyboard) // Klavye açılınca tab bar yukarı kaymasın
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
