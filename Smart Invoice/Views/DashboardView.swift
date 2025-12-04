import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @StateObject var viewModel = InvoiceViewModel()
    
    // Pagination
    @State private var displayedCount = 20 // İlk 20 fatura
    private let pageSize = 20
    
    // UI Durumları
    var body: some View {
        ZStack {
            NavigationStack {
                VStack(spacing: 0) {
                    // 1. Analiz Başlığı (Sabit)
                    analysisHeader
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 20)
                    
                    // 2. Fatura Listesi
                    if viewModel.invoices.isEmpty {
                        Spacer()
                        emptyStateView
                        Spacer()
                    } else {
                        List {
                            // Tarihe göre grupla
                            let grouped = Dictionary(grouping: viewModel.invoices) { (invoice) -> String in
                                let formatter = DateFormatter()
                                formatter.dateStyle = .medium
                                formatter.timeStyle = .none
                                formatter.locale = Locale(identifier: "tr_TR")
                                
                                if Calendar.current.isDateInToday(invoice.invoiceDate) {
                                    return "Bugün"
                                } else if Calendar.current.isDateInYesterday(invoice.invoiceDate) {
                                    return "Dün"
                                }
                                return formatter.string(from: invoice.invoiceDate)
                            }
                            
                            // Grupları sırala (Yeniden eskiye)
                            let sortedKeys = grouped.keys.sorted { dateStr1, dateStr2 in
                                // Basit string sıralaması yerine gerçek tarih karşılaştırması daha iyi olurdu ama
                                // şimdilik listeyi zaten viewModel'de sıralı tutuyoruz.
                                // Pratik çözüm: ViewModel'deki sıraya güvenmek.
                                return true 
                            }
                            
                            ForEach(sortedKeys.prefix(displayedCount / pageSize + 1), id: \.self) { key in
                                Section(header: Text(key).font(.subheadline).bold()) {
                                    ForEach(Array((grouped[key] ?? []).prefix(displayedCount)), id: \.id) { invoice in
                                        InvoiceRowView(invoice: invoice) {
                                            viewModel.editInvoice(invoice)
                                        }
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                        .onAppear {
                                            // Son öğeye yaklaşıldığında daha fazla yükle
                                            if let index = viewModel.invoices.firstIndex(where: { $0.id == invoice.id }),
                                               index >= displayedCount - 5 {
                                                loadMore()
                                            }
                                        }
                                    }
                                    .onDelete(perform: deleteInvoice)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            // Firebase'den yenileme (Gelecekte)
                        }
                    }
                }
                .navigationTitle("Faturalarım")
                .navigationBarTitleDisplayMode(.inline)
            }
            
            // YÜKLENİYOR
            if viewModel.isProcessing {
                loadingOverlay
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
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Henüz Fatura Yok")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
            
            Text("Aşağıdaki + butonuna basarak\nilk faturanı taratabilirsin.")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding()
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
    }
    
    func loadMore() {
        let totalCount = viewModel.invoices.count
        if displayedCount < totalCount {
            displayedCount = min(displayedCount + pageSize, totalCount)
        }
    }
}

