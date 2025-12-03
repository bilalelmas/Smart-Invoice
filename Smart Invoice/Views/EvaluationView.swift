import SwiftUI

struct EvaluationView: View {
    @StateObject private var service = EvaluationService()
    
    var body: some View {
        NavigationStack {
            VStack {
                if service.isRunning {
                    ProgressView("Test Çalışıyor...")
                        .scaleEffect(1.5)
                        .padding()
                } else {
                    // Skor Kartı
                    VStack(spacing: 10) {
                        Text("Genel Doğruluk Skoru")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        Text(String(format: "%.1f%%", service.overallScore))
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(scoreColor)
                    }
                    .padding()
                    
                    // Sonuç Listesi
                    List(service.results) { result in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(result.fileName)
                                    .font(.headline)
                                Text(result.details)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Text(String(format: "%.0f%%", result.score))
                                .font(.headline)
                                .foregroundColor(result.isSuccess ? .green : .red)
                        }
                    }
                    
                    Button(action: { service.runEvaluation() }) {
                        Text("Testi Başlat")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding()
                }
            }
            .navigationTitle("Doğruluk Testi")
        }
    }
    
    var scoreColor: Color {
        if service.overallScore >= 90 { return .green }
        if service.overallScore >= 70 { return .orange }
        return .red
    }
}
