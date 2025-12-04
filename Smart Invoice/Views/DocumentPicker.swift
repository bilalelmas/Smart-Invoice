import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    // Artık Data yerine URL döndüreceğiz, çünkü dosyayı kopyalayıp yolunu vereceğiz
    var onSelect: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // PDF ve Resim türlerini destekle
        let types: [UTType] = [.pdf, .image, .png, .jpeg]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let selectedURL = urls.first else {
                print("❌ DocumentPicker: Hiç dosya seçilmedi")
                return
            }
            
            print("📄 DocumentPicker: Dosya seçildi: \(selectedURL.lastPathComponent)")
            
            // 1. Güvenli erişimi başlat
            let canAccess = selectedURL.startAccessingSecurityScopedResource()
            print("🔐 Security scoped resource erişimi: \(canAccess)")
            
            defer {
                if canAccess {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }
            
            // 2. Dosyayı uygulamanın kendi "Temp" klasörüne kopyala
            // Bu adım "Permission Denied" hatasını çözer.
            do {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "_" + selectedURL.lastPathComponent)
                
                // Eğer eski dosya varsa sil
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                
                // Dosyayı kopyala
                try FileManager.default.copyItem(at: selectedURL, to: tempURL)
                print("✅ Dosya kopyalandı: \(tempURL.path)")
                
                // 3. Artık güvenli olan yerel URL'i geri döndür
                parent.onSelect(tempURL)
                
            } catch {
                print("❌ Dosya kopyalama hatası: \(error.localizedDescription)")
                print("   Kaynak: \(selectedURL.path)")
                print("   Hata detayı: \(error)")
            }
        }
    }
}
