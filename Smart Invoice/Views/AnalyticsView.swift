import SwiftUI
import Charts

struct AnalyticsView: View {
    @ObservedObject var viewModel: InvoiceViewModel
    
    // Filtreleme Seçenekleri
    @State private var selectedTimeRange: TimeRange = .thisMonth
    @State private var selectedChartType: ChartType = .spending
    
    // Grafik Etkileşimi
    @State private var selectedDate: Date?
    @State private var selectedAmount: Double?
    @State private var selectedVendor: String?
    
    enum TimeRange: String, CaseIterable {
        case thisWeek = "Bu Hafta"
        case thisMonth = "Bu Ay"
        case lastMonth = "Geçen Ay"
        case last3Months = "Son 3 Ay"
        case allTime = "Tümü"
    }
    
    enum ChartType: String, CaseIterable {
        case spending = "Harcama"
        case tax = "KDV"
        case vendor = "Satıcı"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    timeRangePicker
                    summaryCards
                    chartTypePicker
                    
                    // Seçilen grafik tipine göre göster
                    switch selectedChartType {
                    case .spending:
                        spendingTrendChart
                    case .tax:
                        taxAnalysisChart
                    case .vendor:
                        vendorDistributionChart
                    }
                    
                    // Ekstra analizler
                    weeklyTrendChart
                    taxBreakdownChart
                    
                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .navigationTitle("Finansal Analiz")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            exportToCSV()
                        }) {
                            Label("CSV Olarak Dışa Aktar", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(action: {
                            shareAnalytics()
                        }) {
                            Label("Paylaş", systemImage: "square.and.arrow.up.on.square")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
        }
    }
    
    // MARK: - View Components
    
    private var timeRangePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            selectedTimeRange = range
                            selectedDate = nil
                            selectedAmount = nil
                        }
                    }) {
                        Text(range.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedTimeRange == range ? .semibold : .regular)
                            .foregroundColor(selectedTimeRange == range ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedTimeRange == range ? Color.blue : Color(.systemGray5))
                            .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var chartTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ChartType.allCases, id: \.self) { type in
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            selectedChartType = type
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: iconForChartType(type))
                            Text(type.rawValue)
                        }
                        .font(.subheadline)
                        .fontWeight(selectedChartType == type ? .semibold : .regular)
                        .foregroundColor(selectedChartType == type ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selectedChartType == type ? Color.purple : Color(.systemGray5))
                        .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func iconForChartType(_ type: ChartType) -> String {
        switch type {
        case .spending: return "chart.bar.fill"
        case .tax: return "percent"
        case .vendor: return "building.2.fill"
        }
    }
    
    private var summaryCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                SummaryCard(
                    title: "Toplam Harcama",
                    amount: calculateTotalAmount(),
                    icon: "creditcard.fill",
                    color: Color(hex: "4e54c8"),
                    trend: calculateSpendingTrend()
                )
                SummaryCard(
                    title: "Toplam KDV",
                    amount: calculateTotalTax(),
                    icon: "percent",
                    color: .orange,
                    trend: calculateTaxTrend()
                )
                SummaryCard(
                    title: "Matrah",
                    amount: calculateTotalBase(),
                    icon: "doc.text.fill",
                    color: .blue,
                    trend: nil
                )
                SummaryCard(
                    title: "Fatura Sayısı",
                    amount: Double(filteredInvoices.count),
                    icon: "doc.text.fill",
                    color: .green,
                    trend: nil,
                    isCount: true
                )
            }
            .padding(.horizontal)
        }
    }
    
    private var spendingTrendChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Harcama Trendi")
                        .font(.headline)
                    Text(selectedTimeRange.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let amount = selectedAmount, let date = selectedDate {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(date.formatted(.dateTime.day().month()))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatCurrency(amount))
                            .font(.subheadline).bold()
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            
            spendingChart
        }
    }
    
    private var taxAnalysisChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("KDV Analizi")
                        .font(.headline)
                    Text("KDV oranlarına göre dağılım")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            
            Chart {
                ForEach(getTaxRateData()) { data in
                    BarMark(
                        x: .value("KDV Oranı", "\(data.taxRate)%"),
                        y: .value("Tutar", data.amount)
                    )
                    .foregroundStyle(by: .value("KDV", data.taxRate))
                    .cornerRadius(6)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.2))
                    AxisValueLabel() {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)₺")
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 250)
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 10)
            .padding(.horizontal)
        }
    }
    
    private var weeklyTrendChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Haftalık Trend")
                        .font(.headline)
                    Text("Son 4 hafta karşılaştırması")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            
            Chart {
                ForEach(getWeeklyData()) { data in
                    LineMark(
                        x: .value("Hafta", data.week),
                        y: .value("Tutar", data.amount)
                    )
                    .foregroundStyle(Color(hex: "4e54c8"))
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    .symbol {
                        Circle()
                            .fill(Color(hex: "4e54c8"))
                            .frame(width: 8, height: 8)
                    }
                    
                    AreaMark(
                        x: .value("Hafta", data.week),
                        y: .value("Tutar", data.amount)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "4e54c8").opacity(0.3), Color(hex: "4e54c8").opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.2))
                    AxisValueLabel() {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)₺")
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 200)
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 10)
            .padding(.horizontal)
        }
    }
    
    private var taxBreakdownChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("KDV Dağılımı")
                        .font(.headline)
                    Text("KDV oranlarına göre detay")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            
            VStack(spacing: 12) {
                ForEach(getTaxRateData().sorted(by: { $0.taxRate > $1.taxRate })) { data in
                    HStack {
                        Text("\(data.taxRate)% KDV")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(width: 80, alignment: .leading)
                        
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 24)
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(colorForTaxRate(data.taxRate))
                                    .frame(width: geometry.size.width * CGFloat(data.amount / getTaxRateData().map { $0.amount }.reduce(0, +)), height: 24)
                            }
                        }
                        .frame(height: 24)
                        
                        Text(formatCurrency(data.amount))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(width: 80, alignment: .trailing)
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 10)
            .padding(.horizontal)
        }
    }
    
    private func colorForTaxRate(_ rate: Int) -> Color {
        switch rate {
        case 1: return .green
        case 10: return .orange
        case 20: return .red
        default: return .blue
        }
    }
    
    private var spendingChart: some View {
        Chart {
            ForEach(getDailyData()) { data in
                BarMark(
                    x: .value("Gün", data.date, unit: .day),
                    y: .value("Tutar", data.amount)
                )
                .foregroundStyle(LinearGradient(
                    colors: [Color(hex: "4e54c8"), Color(hex: "8f94fb")],
                    startPoint: .bottom,
                    endPoint: .top
                ))
                .cornerRadius(4)
                
                if let selectedDate, Calendar.current.isDate(selectedDate, inSameDayAs: data.date) {
                    RuleMark(x: .value("Seçili", selectedDate))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5]))
                        .foregroundStyle(Color.orange)
                }
            }
        }
        .chartOverlay { proxy in
            chartOverlay(proxy: proxy)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.gray.opacity(0.2))
                AxisValueLabel() {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue)₺")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine().foregroundStyle(Color.gray.opacity(0.1))
                AxisTick().foregroundStyle(Color.gray.opacity(0.2))
                AxisValueLabel(format: .dateTime.day().month())
            }
        }
        .frame(height: 250)
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 10)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func chartOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Safely unwrap the plot frame anchor before using it
                            guard let plotFrame = proxy.plotFrame else { return }
                            let plotOrigin = geometry[plotFrame].origin
                            let x = value.location.x - plotOrigin.x
                            if let date: Date = proxy.value(atX: x) {
                                updateSelectedDate(date: date)
                            }
                        }
                        .onEnded { _ in
                            selectedDate = nil
                            selectedAmount = nil
                        }
                )
        }
    }
    
    private func updateSelectedDate(date: Date) {
        let dailyData = getDailyData()
        var closestData: DailyData?
        var minDistance: TimeInterval = .infinity
        
        for data in dailyData {
            let distance = abs(data.date.timeIntervalSince(date))
            if distance < minDistance {
                minDistance = distance
                closestData = data
            }
        }
        
        if let closest = closestData {
            selectedDate = closest.date
            selectedAmount = closest.amount
        }
    }
    
    private var vendorDistributionChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tedarikçi Dağılımı")
                .font(.headline)
                .padding(.horizontal)
            
            if getVendorData().isEmpty {
                Text("Henüz veri yok")
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
            } else {
                Chart {
                    ForEach(getVendorData()) { data in
                        SectorMark(
                            angle: .value("Tutar", data.amount),
                            innerRadius: .ratio(0.6),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Satıcı", data.vendor))
                        .cornerRadius(5)
                    }
                }
                .frame(height: 250)
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.05), radius: 10)
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Hesaplamalar
    
    func calculateTotalAmount() -> Double {
        filteredInvoices.reduce(0) { $0 + $1.totalAmount }
    }
    
    func calculateTotalTax() -> Double {
        filteredInvoices.reduce(0) { $0 + $1.taxAmount }
    }
    
    func calculateTotalBase() -> Double {
        calculateTotalAmount() - calculateTotalTax()
    }
    
    func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: NSNumber(value: value)) ?? "₺0,00"
    }
    
    var filteredInvoices: [Invoice] {
        let calendar = Calendar.current
        let now = Date()
        
        return viewModel.invoices.filter { invoice in
            switch selectedTimeRange {
            case .thisWeek:
                return calendar.isDate(invoice.invoiceDate, equalTo: now, toGranularity: .weekOfYear)
            case .thisMonth:
                return calendar.isDate(invoice.invoiceDate, equalTo: now, toGranularity: .month)
            case .lastMonth:
                guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else { return false }
                return calendar.isDate(invoice.invoiceDate, equalTo: lastMonth, toGranularity: .month)
            case .last3Months:
                guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) else { return false }
                return invoice.invoiceDate >= threeMonthsAgo
            case .allTime:
                return true
            }
        }
    }
    
    // Grafik Veri Modelleri
    struct DailyData: Identifiable {
        let id = UUID()
        let date: Date
        let amount: Double
    }
    
    struct VendorData: Identifiable {
        let id = UUID()
        let vendor: String
        let amount: Double
    }
    
    func getDailyData() -> [DailyData] {
        let grouped = Dictionary(grouping: filteredInvoices) { invoice in
            Calendar.current.startOfDay(for: invoice.invoiceDate)
        }
        return grouped.map { DailyData(date: $0.key, amount: $0.value.reduce(0) { $0 + $1.totalAmount }) }
            .sorted { $0.date < $1.date }
    }
    
    func getVendorData() -> [VendorData] {
        let grouped = Dictionary(grouping: filteredInvoices) { $0.merchantName }
        return grouped.map { VendorData(vendor: $0.key, amount: $0.value.reduce(0) { $0 + $1.totalAmount }) }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }
    }
    
    struct TaxRateData: Identifiable {
        let id = UUID()
        let taxRate: Int
        let amount: Double
    }
    
    struct WeeklyData: Identifiable {
        let id = UUID()
        let week: String
        let amount: Double
    }
    
    func getTaxRateData() -> [TaxRateData] {
        var taxRates: [Int: Double] = [:]
        
        for invoice in filteredInvoices {
            // KDV oranını hesapla (basit yaklaşım)
            let taxRate: Int
            if invoice.taxAmount > 0 && invoice.subTotal > 0 {
                let calculatedRate = Int((invoice.taxAmount / invoice.subTotal) * 100)
                // En yakın standart KDV oranına yuvarla
                if calculatedRate <= 1 {
                    taxRate = 1
                } else if calculatedRate <= 10 {
                    taxRate = 10
                } else {
                    taxRate = 20
                }
            } else {
                taxRate = 0
            }
            
            taxRates[taxRate, default: 0] += invoice.taxAmount
        }
        
        return taxRates.map { TaxRateData(taxRate: $0.key, amount: $0.value) }
    }
    
    func getWeeklyData() -> [WeeklyData] {
        let calendar = Calendar.current
        let now = Date()
        var weeklyData: [WeeklyData] = []
        
        for i in 0..<4 {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -i, to: now),
                  let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else { continue }
            
            let weekInvoices = filteredInvoices.filter { invoice in
                invoice.invoiceDate >= weekStart && invoice.invoiceDate <= weekEnd
            }
            
            let total = weekInvoices.reduce(0) { $0 + $1.totalAmount }
            let weekLabel = calendar.component(.weekOfYear, from: weekStart)
            weeklyData.append(WeeklyData(week: "Hafta \(weekLabel)", amount: total))
        }
        
        return weeklyData.reversed()
    }
    
    func calculateSpendingTrend() -> Double? {
        guard selectedTimeRange == .thisMonth || selectedTimeRange == .lastMonth else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        
        guard let previousPeriodStart = calendar.date(byAdding: .month, value: selectedTimeRange == .thisMonth ? -1 : -2, to: now),
              let previousPeriodEnd = calendar.date(byAdding: .month, value: selectedTimeRange == .thisMonth ? 0 : -1, to: now) else {
            return nil
        }
        
        let currentTotal = filteredInvoices.reduce(0) { $0 + $1.totalAmount }
        let previousInvoices = viewModel.invoices.filter { invoice in
            invoice.invoiceDate >= previousPeriodStart && invoice.invoiceDate < previousPeriodEnd
        }
        let previousTotal = previousInvoices.reduce(0) { $0 + $1.totalAmount }
        
        guard previousTotal > 0 else { return nil }
        return ((currentTotal - previousTotal) / previousTotal) * 100
    }
    
    func calculateTaxTrend() -> Double? {
        return calculateSpendingTrend() // Aynı trend hesaplaması
    }
    
    func exportToCSV() {
        // CSV export işlevselliği (gelecekte implement edilecek)
        print("📊 CSV export başlatılıyor...")
    }
    
    func shareAnalytics() {
        // Paylaşma işlevselliği (gelecekte implement edilecek)
        print("📤 Analiz paylaşılıyor...")
    }
}

// MARK: - Özet Kartı Bileşeni
struct SummaryCard: View {
    let title: String
    let amount: Double
    let icon: String
    let color: Color
    var trend: Double? = nil
    var isCount: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [color.opacity(0.2), color.opacity(0.1)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 18, weight: .medium))
                }
                Spacer()
                
                if let trend = trend {
                    HStack(spacing: 4) {
                        Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                        Text("\(abs(trend), specifier: "%.1f")%")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(trend >= 0 ? .green : .red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background((trend >= 0 ? Color.green : Color.red).opacity(0.1))
                    .cornerRadius(6)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if isCount {
                    Text("\(Int(amount))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                } else {
                    Text(formatCurrency(amount))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(16)
        .frame(width: 170)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
    
    func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "₺0"
    }
}
