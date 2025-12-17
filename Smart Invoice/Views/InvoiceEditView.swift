import SwiftUI

struct InvoiceEditView: View {
    @Binding var invoice: Invoice
    var onSave: () -> Void
    var onCancel: () -> Void
    var image: UIImage? // Debug için görsel
    
    // Para birimi formatlayıcı (sadece gösterim için)
    private let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "TRY"
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter
    }()
    
    // Fiyat alanları için String state'leri (düzenleme kolaylığı için)
    @State private var totalAmountText: String = ""
    @State private var subTotalText: String = ""
    @State private var taxAmountText: String = ""
    @State private var isInitialized: Bool = false
    
    // Form validasyonu ve geri bildirim
    @State private var validationErrors: [String] = []
    @State private var showSuccessMessage = false
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var hasUnsavedChanges = false
    
    // View yüklendiğinde değerleri String'e çevir (sadece ilk yüklemede)
    private func initializeAmountTexts() {
        guard !isInitialized else { return }
        // Invoice değerlerinden String'e çevir
        totalAmountText = formatAmountForEditing(invoice.totalAmount)
        subTotalText = formatAmountForEditing(invoice.subTotal)
        taxAmountText = formatAmountForEditing(invoice.taxAmount)
        isInitialized = true
    }
    
    // Tutarı düzenlenebilir formata çevir (nokta/ virgül olmadan)
    private func formatAmountForEditing(_ amount: Double) -> String {
        if amount == 0 { return "" }
        // Türkçe format: 1250.50 -> "1250,50"
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = ","
        formatter.groupingSeparator = "."
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }
    
    // String'den Double'a çevir
    private func parseAmount(_ text: String) -> Double {
        let cleaned = text.replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0.0
    }
    
    // Form validasyonu
    private func validateForm() -> Bool {
        validationErrors.removeAll()
        
        if invoice.merchantName.trimmingCharacters(in: .whitespaces).isEmpty {
            validationErrors.append("Satıcı adı boş olamaz")
        }
        
        if invoice.totalAmount <= 0 {
            validationErrors.append("Toplam tutar 0'dan büyük olmalıdır")
        }
        
        // KDV kontrolü: Ara toplam + KDV = Toplam tutar olmalı (tolerans: 0.01)
        let calculatedTotal = invoice.subTotal + invoice.taxAmount
        if abs(calculatedTotal - invoice.totalAmount) > 0.01 {
            validationErrors.append("Ara toplam + KDV, toplam tutara eşit olmalıdır")
        }
        
        return validationErrors.isEmpty
    }
    
    // Auto-save tetikleme (debounce ile)
    private func triggerAutoSave() {
        hasUnsavedChanges = true
        
        // Önceki task'ı iptal et
        autoSaveTask?.cancel()
        
        // Yeni task oluştur (2 saniye sonra)
        autoSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 saniye
            } catch {
                return // Task iptal edildi
            }
            
            if !Task.isCancelled {
                await MainActor.run {
                    if validateForm() {
                        // Sessizce kaydet (kullanıcıya bildirim göster)
                        invoice.totalAmount = parseAmount(totalAmountText)
                        invoice.subTotal = parseAmount(subTotalText)
                        invoice.taxAmount = parseAmount(taxAmountText)
                        
                        // Başarı animasyonu göster
                        withAnimation(.spring(response: 0.3)) {
                            showSuccessMessage = true
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation(.spring(response: 0.3)) {
                                showSuccessMessage = false
                            }
                        }
                    }
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // 0. Görsel Hata Ayıklayıcı (Visual Debugger)
                        if let image = image, !invoice.debugRegions.isEmpty {
                            VStack(alignment: .leading) {
                                Text("Görsel Analiz")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.leading)
                                
                                ZStack {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .cornerRadius(12)
                                        .overlay(
                                            GeometryReader { geometry in
                                                ForEach(invoice.debugRegions) { region in
                                                    // Artık koordinatlar UIKit sisteminde (sol üst köşe)
                                                    // SwiftUI da sol üst köşe kullanır, direkt kullanabiliriz
                                                    
                                                    let w = region.rect.width * geometry.size.width
                                                    let h = region.rect.height * geometry.size.height
                                                    let x = region.rect.origin.x * geometry.size.width
                                                    let y = region.rect.origin.y * geometry.size.height
                                                    
                                                    Rectangle()
                                                        .stroke(colorForRegion(region.type), lineWidth: 2)
                                                        .background(colorForRegion(region.type).opacity(0.2))
                                                        .frame(width: w, height: h)
                                                        .position(x: x + w/2, y: y + h/2)
                                                }
                                            }
                                        )
                                }
                                .frame(height: 300)
                                .padding(.horizontal)
                                
                                // Lejant
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        legendItem(color: .red, text: "Satıcı")
                                        legendItem(color: .green, text: "Tutar")
                                        legendItem(color: .orange, text: "Ara Toplam")
                                        legendItem(color: .purple, text: "KDV")
                                        legendItem(color: .blue, text: "Tablo")
                                        legendItem(color: .yellow, text: "Tarih")
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        // 1. Güven Skoru Kartı
                        confidenceCard
                        
                        // ...
                        

                        
                        // 2. Satıcı Bilgileri
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "SATICI BİLGİLERİ", icon: "building.2.fill")
                            
                            CustomTextField(title: "Firma Adı", text: $invoice.merchantName)
                            CustomTextField(title: "Vergi No", text: $invoice.merchantTaxID, keyboardType: .numberPad)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                        
                        // 3. Fatura Detayları
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "FATURA DETAYLARI", icon: "doc.text.fill")
                            
                            CustomTextField(title: "Fatura No", text: $invoice.invoiceNo)
                            
                            HStack {
                                Text("Fatura Tarihi")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Spacer()
                                DatePicker("", selection: $invoice.invoiceDate, displayedComponents: .date)
                                    .labelsHidden()
                            }
                            .padding(.vertical, 4)
                            
                            CustomTextField(title: "ETTN", text: $invoice.ettn)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                        
                        // 4. Finansal Bilgiler
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "FİNANSAL VERİLER", icon: "turkishlirasign.circle.fill")
                            
                            HStack {
                                Text("Toplam Tutar")
                                    .font(.headline)
                                Spacer()
                                TextField("0,00", text: $totalAmountText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.title3.bold())
                                    .foregroundColor(.blue)
                                    .onChange(of: totalAmountText) { _, newValue in
                                        invoice.totalAmount = parseAmount(newValue)
                                        triggerAutoSave()
                                    }
                                
                                // Güven Uyarısı
                                if let confidence = invoice.confidenceScores["totalAmount"], confidence < 0.7 {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .help("Düşük Güven Skoru: Lütfen kontrol edin")
                                }
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("Ara Toplam (Matrah)")
                                    .font(.subheadline)
                                Spacer()
                                TextField("0,00", text: $subTotalText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .onChange(of: subTotalText) { _, newValue in
                                        invoice.subTotal = parseAmount(newValue)
                                        triggerAutoSave()
                                    }
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("KDV")
                                    .font(.subheadline)
                                Spacer()
                                TextField("0,00", text: $taxAmountText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .onChange(of: taxAmountText) { _, newValue in
                                        invoice.taxAmount = parseAmount(newValue)
                                        triggerAutoSave()
                                    }
                            }
                            
                            // Validasyon uyarıları
                            if !validationErrors.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(validationErrors, id: \.self) { error in
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.orange)
                                                .font(.caption)
                                            Text(error)
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                        
                        // Kaydet Butonu
                        Button(action: {
                            // Son değişiklikleri kaydet
                            invoice.totalAmount = parseAmount(totalAmountText)
                            invoice.subTotal = parseAmount(subTotalText)
                            invoice.taxAmount = parseAmount(taxAmountText)
                            
                            if validateForm() {
                                // Haptic feedback
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                                
                                onSave()
                                hasUnsavedChanges = false
                            } else {
                                // Hata feedback
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.error)
                            }
                        }) {
                            HStack {
                                if !validationErrors.isEmpty {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                Text(validationErrors.isEmpty ? "Değişiklikleri Onayla ve Kaydet" : "Lütfen Hataları Düzeltin")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(validationErrors.isEmpty ? Color.blue : Color.orange)
                            .cornerRadius(16)
                            .shadow(radius: 5)
                        }
                        .padding(.top, 10)
                        .disabled(!validationErrors.isEmpty)
                        
                        Spacer(minLength: 50)
                    }
                    .padding()
                }
            }
            .navigationTitle("Fatura Doğrulama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { onCancel() }
                }
            }
            .overlay(alignment: .top) {
                // Auto-save başarı mesajı
                if showSuccessMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                        Text("Otomatik kaydedildi")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onAppear {
                initializeAmountTexts()
                _ = validateForm() // İlk validasyonu çalıştır
            }
            .onChange(of: invoice.totalAmount) { _, _ in
                // Invoice değerleri değiştiğinde (dışarıdan güncelleme) state'leri güncelle
                if !isInitialized {
                    initializeAmountTexts()
                }
            }
            .onChange(of: invoice.merchantName) { _, _ in
                triggerAutoSave()
            }
        }
    }
    
    // MARK: - Subviews
    
    var confidenceCard: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("AI Güven Skoru")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Yapay zeka bu faturayı %\(Int(invoice.confidenceScore * 100)) oranında doğru okuduğunu düşünüyor.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 6)
                    .frame(width: 50, height: 50)
                
                Circle()
                    .trim(from: 0, to: CGFloat(invoice.confidenceScore))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))
                
                Text("%\(Int(invoice.confidenceScore * 100))")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(
            LinearGradient(gradient: Gradient(colors: [invoice.confidenceScore > 0.7 ? Color.green : Color.orange, Color.blue]), startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(16)
        .shadow(radius: 5)
    }
}

// MARK: - Helper Functions

func colorForRegion(_ type: OCRRegion.RegionType) -> Color {
    switch type {
    case .seller: return .red
    case .total: return .green
    case .subTotal: return .orange
    case .tax: return .purple
    case .table: return .blue
    case .date: return .yellow
    }
}

func legendItem(color: Color, text: String) -> some View {
    HStack(spacing: 4) {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
        Text(text)
            .font(.caption)
            .foregroundColor(.gray)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color.white)
    .cornerRadius(8)
    .shadow(radius: 1)
}

// MARK: - Helper Components

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.gray)
        }
    }
}

struct CustomTextField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)
            
            TextField("", text: $text)
                .padding(10)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(8)
                .keyboardType(keyboardType)
        }
    }
}
