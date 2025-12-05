import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @StateObject var viewModel = InvoiceViewModel()
    
    // Pagination
    @State private var displayedCount = 20 // İlk 20 fatura
    private let pageSize = 20
    
    // Filtreleme UI Durumları
    @State private var showFilters = false
    @State private var showDatePicker = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var minAmount: Double = 0
    @State private var maxAmount: Double = 100000
    
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
                    
                    // 1.5 Arama ve Filtreleme
                    searchAndFilterBar
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                    
                    // 2. Fatura Listesi
                    if viewModel.filteredInvoices.isEmpty {
                        Spacer()
                        emptyStateView
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                // Tarihe göre grupla (filtrelenmiş listeyi kullan)
                                let grouped = Dictionary(grouping: viewModel.filteredInvoices) { (invoice) -> String in
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
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Section Header
                                        HStack {
                                            Text(key)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.top, 8)
                                        
                                        // Invoice Cards
                                        ForEach(Array((grouped[key] ?? []).prefix(displayedCount)), id: \.id) { invoice in
                                            InvoiceRowView(invoice: invoice) {
                                                viewModel.editInvoice(invoice)
                                            }
                                            .padding(.horizontal, 16)
                                            .transition(.asymmetric(
                                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)
                                            ))
                                            .onAppear {
                                                // Son öğeye yaklaşıldığında daha fazla yükle
                                                if let index = viewModel.filteredInvoices.firstIndex(where: { $0.id == invoice.id }),
                                                   index >= displayedCount - 5 {
                                                    loadMore()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .refreshable {
                            await refreshInvoices()
                        }
                    }
                }
                .navigationTitle("Faturalarım")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if viewModel.hasActiveFilters {
                            Button(action: {
                                viewModel.clearFilters()
                            }) {
                                Label("Filtreleri Temizle", systemImage: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
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
        .sheet(isPresented: $showFilters) {
            filterSheet
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
                VStack(alignment: .leading, spacing: 4) {
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
                    Text("\(viewModel.filteredInvoices.count) Belge")
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
                        .contentTransition(.numericText())
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
                        .contentTransition(.numericText())
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
                    .contentTransition(.numericText())
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.16, blue: 0.42), // #1a2a6c
                    Color(red: 0.70, green: 0.12, blue: 0.12)  // #b21f1f
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
    
    // MARK: - Arama ve Filtreleme UI
    
    var searchAndFilterBar: some View {
        VStack(spacing: 12) {
            // Arama Çubuğu
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Satıcı, fatura no, ETTN ara...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // Filtre Butonları
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Satıcı Filtresi
                    Menu {
                        ForEach(viewModel.uniqueVendors, id: \.self) { vendor in
                            Button(action: {
                                viewModel.selectedVendor = viewModel.selectedVendor == vendor ? nil : vendor
                            }) {
                                HStack {
                                    Text(vendor)
                                    if viewModel.selectedVendor == vendor {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        FilterChip(
                            title: "Satıcı",
                            value: viewModel.selectedVendor,
                            icon: "building.2"
                        )
                    }
                    
                    // Tarih Filtresi
                    Button(action: {
                        showDatePicker = true
                    }) {
                        FilterChip(
                            title: "Tarih",
                            value: viewModel.dateRange != nil ? "Seçili" : nil,
                            icon: "calendar"
                        )
                    }
                    
                    // Durum Filtresi
                    Menu {
                        ForEach(InvoiceStatus.allCases, id: \.self) { status in
                            Button(action: {
                                viewModel.selectedStatus = viewModel.selectedStatus == status ? nil : status
                            }) {
                                HStack {
                                    Text(status.rawValue)
                                    if viewModel.selectedStatus == status {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        FilterChip(
                            title: "Durum",
                            value: viewModel.selectedStatus?.rawValue,
                            icon: "checkmark.circle"
                        )
                    }
                    
                    // Tutar Filtresi
                    Button(action: {
                        // Tutar aralığı için sheet göster
                        showFilters = true
                    }) {
                        FilterChip(
                            title: "Tutar",
                            value: viewModel.amountRange != nil ? "Seçili" : nil,
                            icon: "turkishlirasign.circle"
                        )
                    }
                    
                    // Tüm Filtreler
                    Button(action: {
                        showFilters = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text("Filtreler")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(viewModel.hasActiveFilters ? Color.blue : Color(.systemGray5))
                        .foregroundColor(viewModel.hasActiveFilters ? .white : .primary)
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .sheet(isPresented: $showDatePicker) {
            dateRangePickerSheet
        }
    }
    
    var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Tarih Aralığı") {
                    DatePicker("Başlangıç", selection: $startDate, displayedComponents: .date)
                    DatePicker("Bitiş", selection: $endDate, displayedComponents: .date)
                    
                    Button("Tarih Aralığını Uygula") {
                        if startDate <= endDate {
                            viewModel.dateRange = startDate...endDate
                        }
                        showFilters = false
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if viewModel.dateRange != nil {
                        Button("Tarih Filtresini Kaldır") {
                            viewModel.dateRange = nil
                        }
                        .foregroundColor(.red)
                    }
                }
                
                Section("Durum Filtresi") {
                    Picker("Durum", selection: $viewModel.selectedStatus) {
                        Text("Tümü").tag(nil as InvoiceStatus?)
                        ForEach(InvoiceStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status as InvoiceStatus?)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if viewModel.selectedStatus != nil {
                        Button("Durum Filtresini Kaldır") {
                            viewModel.selectedStatus = nil
                        }
                        .foregroundColor(.red)
                    }
                }
                
                Section("Tutar Aralığı") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Min: \(formatCurrency(minAmount))")
                            Spacer()
                            Text("Max: \(formatCurrency(maxAmount))")
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                        
                        HStack {
                            TextField("Min", value: $minAmount, format: .number)
                                .keyboardType(.decimalPad)
                            Text("-")
                            TextField("Max", value: $maxAmount, format: .number)
                                .keyboardType(.decimalPad)
                        }
                    }
                    
                    Button("Tutar Aralığını Uygula") {
                        if minAmount <= maxAmount {
                            viewModel.amountRange = minAmount...maxAmount
                        }
                        showFilters = false
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if viewModel.amountRange != nil {
                        Button("Tutar Filtresini Kaldır") {
                            viewModel.amountRange = nil
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Filtreler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") {
                        showFilters = false
                    }
                }
            }
        }
    }
    
    var dateRangePickerSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Başlangıç Tarihi", selection: $startDate, displayedComponents: .date)
                DatePicker("Bitiş Tarihi", selection: $endDate, displayedComponents: .date)
                
                Button("Uygula") {
                    if startDate <= endDate {
                        viewModel.dateRange = startDate...endDate
                    }
                    showDatePicker = false
                }
                .buttonStyle(.borderedProminent)
                
                if viewModel.dateRange != nil {
                    Button("Filtreyi Kaldır") {
                        viewModel.dateRange = nil
                        showDatePicker = false
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Tarih Aralığı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") {
                        showDatePicker = false
                    }
                }
            }
        }
    }
    
    // Yardımcı Hesaplamalar
    func calculateTotalAmount() -> Double {
        viewModel.filteredInvoices.reduce(0) { $0 + $1.totalAmount }
    }
    
    func calculateTotalTax() -> Double {
        viewModel.filteredInvoices.reduce(0) { $0 + $1.taxAmount }
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
        VStack(spacing: 24) {
            // Animated Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.bottom, 8)
            
            VStack(spacing: 12) {
                Text(viewModel.hasActiveFilters ? "Filtreye Uygun Fatura Bulunamadı" : "Henüz Fatura Yok")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(viewModel.hasActiveFilters 
                     ? "Filtreleri değiştirerek tekrar deneyebilirsin."
                     : "Aşağıdaki + butonuna basarak\nilk faturanı taratabilirsin.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            
            if viewModel.hasActiveFilters {
                Button(action: {
                    viewModel.clearFilters()
                }) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Filtreleri Temizle")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
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
        let totalCount = viewModel.filteredInvoices.count
        if displayedCount < totalCount {
            withAnimation(.easeInOut(duration: 0.3)) {
                displayedCount = min(displayedCount + pageSize, totalCount)
            }
        }
    }
    
    @MainActor
    func refreshInvoices() async {
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Firebase'den yenileme (gelecekte implement edilecek)
        // Şimdilik sadece UI'ı yeniliyoruz
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 saniye
        
        // ViewModel'deki faturaları yeniden yükle
        // await viewModel.refreshInvoices()
    }
}

// MARK: - FilterChip Component

struct FilterChip: View {
    let title: String
    let value: String?
    let icon: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
            if let value = value {
                Text("• \(value)")
                    .fontWeight(.semibold)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(value != nil ? Color.blue.opacity(0.2) : Color(.systemGray5))
        .foregroundColor(value != nil ? .blue : .primary)
        .cornerRadius(16)
    }
}

