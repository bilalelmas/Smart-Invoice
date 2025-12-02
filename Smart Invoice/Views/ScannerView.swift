import SwiftUI
import VisionKit

/// iOS'in yerleşik belge tarama arayüzünü (VNDocumentCameraViewController)
/// SwiftUI içinde kullanmamızı sağlayan sarmalayıcı (Wrapper) yapı.
struct ScannerView: UIViewControllerRepresentable {
    
    // Tarama bitince tetiklenecek olay (Taranan resimlerle döner)
    var didFinishScanning: ((_ result: Result<[UIImage], Error>) -> Void)
    
    // İptal edilince tetiklenecek olay
    var didCancelScanning: () -> Void
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scannerViewController = VNDocumentCameraViewController()
        scannerViewController.delegate = context.coordinator
        return scannerViewController
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        // Güncelleme gerekmez, view statiktir.
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(with: self)
    }
    
    // UIKit delegasyonunu yöneten koordinatör sınıfı
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let scannerView: ScannerView
        
        init(with scannerView: ScannerView) {
            self.scannerView = scannerView
        }
        
        // Tarama başarılı olduğunda
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var scannedPages = [UIImage]()
            
            // Taranan tüm sayfaları al (Biz şimdilik sadece ilk sayfayı işleyeceğiz)
            for i in 0..<scan.pageCount {
                scannedPages.append(scan.imageOfPage(at: i))
            }
            
            scannerView.didFinishScanning(.success(scannedPages))
        }
        
        // İptal edildiğinde
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            scannerView.didCancelScanning()
        }
        
        // Hata olduğunda
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            scannerView.didFinishScanning(.failure(error))
        }
    }
}
