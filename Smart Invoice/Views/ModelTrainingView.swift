import SwiftUI
import Charts

/// Model eğitimi ve analiz ekranı
struct ModelTrainingView: View {
    private let service = ModelTrainingService()
    @State private var analysis: TrainingAnalysis?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var csvExport: String?
    
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
                        Text("Hata: \(error)")
                            .foregroundColor(.red)
                            .padding()
                    } else {
                        Text("Analiz başlatılmadı")
                            .foregroundColor(.secondary)
                            .padding()
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
                }
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
            
            if let csv = csvExport {
                ShareLink(item: csv, preview: SharePreview("Training Data CSV")) {
                    Label("Paylaş", systemImage: "square.and.arrow.up.on.square")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                }
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
            csvExport = try await service.exportTrainingDataToCSV()
        } catch {
            errorMessage = "Export hatası: \(error.localizedDescription)"
        }
        
        isLoading = false
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

