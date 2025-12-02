import SwiftUI
import FirebaseCore // Firebase'in kalbi burası

// 1. ADIM: AppDelegate sınıfını tanımlıyoruz (Motoru başlatan yer)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Firebase'i yapılandır
        FirebaseApp.configure()
        print("🔥 Firebase başarıyla başlatıldı!")
        return true
    }
}

@main
struct SmartInvoiceApp: App {
    // 2. ADIM: SwiftUI'a bu AppDelegate'i kullanmasını söylüyoruz
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            // Uygulama açılınca DashboardView        WindowGroup {
            MainTabView()
        }
    }
}
