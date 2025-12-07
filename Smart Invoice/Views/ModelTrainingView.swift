import SwiftUI
import Charts

/// Model eğitimi ve analiz ekranı
struct ModelTrainingView: View {
    private let service = ModelTrainingService()
    @State private var analysis: TrainingAnalysis?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var csvExport: String?
    @State private var csvFileURL: URL?
    @State private var hasLoadedOnce = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if isLoading {
                        ProgressView("Analiz ediliyor...")
                            .padding()
                    } else if let analysis = analysis {
                        // Özet Kartlar
                        summaryCards(analysis: analysis)
                        
                        // Hata Dağılımı Grafiği
                        errorDistributionChart(analysis: analysis)
                        
                        // Pattern Önerileri
                        patternSuggestions(analysis: analysis)
                        
                        // Export Butonu
                        exportSection
                    } else if let error = errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                            Text("Hata")
                                .font(.headline)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding()
                    } else {
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("Model Eğitimi")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Analiz Et") {
                        Task {
                            await analyzeTrainingData()
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .onAppear {
                // İlk açılışta otomatik analiz başlat
                if !hasLoadedOnce {
                    hasLoadedOnce = true
                    Task {
                        await analyzeTrainingData()
                    }
                }
            }
            .refreshable {
                await analyzeTrainingData()
            }
        }
    }
    
    // MARK: - View Components
    
    private func summaryCards(analysis: TrainingAnalysis) -> some View {
        HStack(spacing: 16) {
            TrainingSummaryCard(
                title: "Toplam Örnek",
                value: "\(analysis.totalSamples)",
                icon: "doc.text.fill",
                color: .blue
            )
            
            TrainingSummaryCard(
                title: "Hata Alanı",
                value: "\(analysis.fieldErrors.count)",
                icon: "exclamationmark.triangle.fill",
                color: .orange
            )
            
            TrainingSummaryCard(
                title: "Öneri",
                value: "\(analysis.patternSuggestions.count)",
                icon: "lightbulb.fill",
                color: .yellow
            )
        }
    }
    
    private func errorDistributionChart(analysis: TrainingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hata Dağılımı")
                .font(.headline)
                .padding(.horizontal)
            
            Chart {
                ForEach(Array(analysis.fieldErrors.sorted(by: { $0.value > $1.value }).prefix(10)), id: \.key) { item in
                    BarMark(
                        x: .value("Alan", item.key),
                        y: .value("Hata Sayısı", item.value)
                    )
                    .foregroundStyle(Color.orange.gradient)
                }
            }
            .frame(height: 250)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(16)
            .padding(.horizontal)
        }
    }
    
    private func patternSuggestions(analysis: TrainingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pattern Önerileri")
                .font(.headline)
                .padding(.horizontal)
            
            if analysis.patternSuggestions.isEmpty {
                Text("Henüz öneri yok")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(Array(analysis.patternSuggestions.enumerated()), id: \.offset) { index, suggestion in
                    PatternSuggestionCard(suggestion: suggestion)
                }
            }
        }
    }
    
    private var exportSection: some View {
        VStack(spacing: 16) {
            Text("Veri Export")
                .font(.headline)
            
            Button(action: {
                Task {
                    await exportToCSV()
                }
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("CSV Olarak Dışa Aktar")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            
            if let csv = csvExport, let url = csvFileURL {
                ShareLink(item: url, preview: SharePreview("Training Data CSV", icon: "doc.text")) {
                    Label("Paylaş", systemImage: "square.and.arrow.up.on.square")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                }
            } else if csvExport != nil {
                Text("CSV hazır, paylaşmak için yukarıdaki butona tıklayın")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    // MARK: - Functions
    
    @MainActor
    private func analyzeTrainingData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            analysis = try await service.analyzeTrainingData()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    @MainActor
    private func exportToCSV() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let csv = try await service.exportTrainingDataToCSV()
            csvExport = csv
            
            // CSV'yi geçici dosyaya kaydet
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "training_data_\(Date().timeIntervalSince1970).csv"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            csvFileURL = fileURL
            
            print("✅ CSV dosyası oluşturuldu: \(fileURL.path)")
        } catch {
            errorMessage = "Export hatası: \(error.localizedDescription)"
            print("❌ CSV export hatası: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(.blue.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("Model Eğitimi")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Henüz eğitim verisi yok")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Faturaları düzenleyip kaydettiğinizde, sistem otomatik olarak öğrenmeye başlayacak.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }
            
            Button(action: {
                Task {
                    await analyzeTrainingData()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Analiz Et")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(12)
            }
        }
        .padding(40)
    }
}

// MARK: - Helper Views

struct TrainingSummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct PatternSuggestionCard: View {
    let suggestion: PatternSuggestion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(suggestion.field)
                    .font(.headline)
                Spacer()
                Text("\(Int(suggestion.confidence * 100))%")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }
            
            Text(suggestion.reason)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Mevcut:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(suggestion.currentPattern)
                    .font(.system(.caption, design: .monospaced))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Önerilen:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(suggestion.suggestedPattern)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

