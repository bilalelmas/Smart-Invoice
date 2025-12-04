import SwiftUI
import Charts

struct AnalyticsView: View {
    @ObservedObject var viewModel: InvoiceViewModel
    
    // Filtreleme Seçenekleri
    @State private var selectedTimeRange: TimeRange = .thisMonth
    
    // Grafik Etkileşimi
    @State private var selectedDate: Date?
    @State private var selectedAmount: Double?
    
    enum TimeRange: String, CaseIterable {
        case thisMonth = "Bu Ay"
        case lastMonth = "Geçen Ay"
        case allTime = "Tümü"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    timeRangePicker
                    summaryCards
                    spendingTrendChart
                    vendorDistributionChart
                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .navigationTitle("Finansal Analiz")
            .background(Color(UIColor.systemGroupedBackground))
        }
    }
    
    // MARK: - View Components
    
    private var timeRangePicker: some View {
        Picker("Zaman Aralığı", selection: $selectedTimeRange) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .onChange(of: selectedTimeRange) {
            selectedDate = nil
            selectedAmount = nil
        }
    }
    
    private var summaryCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                SummaryCard(
                    title: "Toplam Harcama",
                    amount: calculateTotalAmount(),
                    icon: "creditcard.fill",
                    color: Color(hex: "4e54c8")
                )
                SummaryCard(
                    title: "Toplam KDV",
                    amount: calculateTotalTax(),
                    icon: "percent",
                    color: .orange
                )
                SummaryCard(
                    title: "Matrah",
                    amount: calculateTotalBase(),
                    icon: "doc.text.fill",
                    color: .blue
                )
            }
            .padding(.horizontal)
        }
    }
    
    private var spendingTrendChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Harcama Trendi")
                    .font(.headline)
                Spacer()
                if let amount = selectedAmount, let date = selectedDate {
                    VStack(alignment: .trailing) {
                        Text(date.formatted(.dateTime.day().month()))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatCurrency(amount))
                            .font(.caption).bold()
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.horizontal)
            
            spendingChart
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
            case .thisMonth:
                return calendar.isDate(invoice.invoiceDate, equalTo: now, toGranularity: .month)
            case .lastMonth:
                guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else { return false }
                return calendar.isDate(invoice.invoiceDate, equalTo: lastMonth, toGranularity: .month)
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
}

// MARK: - Özet Kartı Bileşeni
struct SummaryCard: View {
    let title: String
    let amount: Double
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .padding(8)
                    .background(color.opacity(0.1))
                    .clipShape(Circle())
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary) // Dark mode uyumlu
                Text(formatCurrency(amount))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary) // Dark mode uyumlu
            }
        }
        .padding()
        .frame(width: 160)
        .background(Color(UIColor.secondarySystemGroupedBackground)) // Dark mode uyumlu
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5)
    }
    
    func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: NSNumber(value: value)) ?? "₺0,00"
    }
}
