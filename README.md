# Smart Invoice 📄

Modern iOS fatura yönetim uygulaması. OCR teknolojisi ile faturaları otomatik tarayın, analiz edin ve yönetin.

## ✨ Özellikler

- 📸 **Otomatik OCR**: PDF ve görsel faturaları tarayarak verileri otomatik çıkarır
- 🔍 **Akıllı Parsing**: Satıcı bilgisi, tutarlar, KDV, ETTN ve diğer fatura detaylarını otomatik tespit eder
- 📊 **Finansal Analiz**: Detaylı grafikler ve trend analizleri ile harcamalarınızı takip edin
- 🔄 **Active Learning**: Kullanıcı düzeltmelerinden öğrenerek zamanla daha iyi sonuçlar üretir
- ☁️ **Firebase Entegrasyonu**: Verileriniz bulutta güvenle saklanır
- 🎨 **Modern UI**: SwiftUI ile tasarlanmış kullanıcı dostu arayüz
- 🔎 **Gelişmiş Filtreleme**: Tarih, tutar, satıcı ve durum bazlı filtreleme
- 📈 **KDV Analizi**: KDV dağılımı ve trend analizleri

## 🛠️ Teknolojiler

- **SwiftUI** - Modern iOS UI framework
- **Vision Framework** - OCR işlemleri
- **Firebase Firestore** - Bulut veri depolama
- **PDFKit** - PDF işleme
- **Core ML** (gelecek) - Makine öğrenmesi entegrasyonu

## 📋 Gereksinimler

- iOS 15.0+
- Xcode 14.0+
- Swift 5.7+
- Firebase hesabı (Firestore için)

## 🚀 Kurulum

1. Repository'yi klonlayın:
```bash
git clone https://github.com/KULLANICI_ADINIZ/Smart-Invoice.git
cd Smart-Invoice
```

2. Firebase yapılandırması:
   - Firebase Console'dan `GoogleService-Info.plist` dosyasını indirin
   - Dosyayı proje kök dizinine ekleyin

3. Xcode'da projeyi açın ve çalıştırın

## 📖 Kullanım

1. **Fatura Tarama**: Ana ekrandan PDF veya görsel seçin
2. **Düzeltme**: OCR sonuçlarını kontrol edip gerekirse düzenleyin
3. **Kaydetme**: Faturayı kaydedin ve Firebase'e senkronize edin
4. **Analiz**: Analytics sekmesinden finansal analizleri görüntüleyin
5. **Model Eğitimi**: Profil sekmesinden model eğitimi ve iyileştirme önerilerini görüntüleyin

## 🏗️ Mimari

- **MVVM Pattern**: ViewModel'ler ile iş mantığı ayrımı
- **Dependency Injection**: Protocol-based servisler ve DIContainer
- **Async/Await**: Modern Swift concurrency
- **Repository Pattern**: Firebase işlemleri için

## 📚 Dokümantasyon

- [Geliştirme Planı](GELISTIRME_PLANI.md)
- [Model Eğitimi Kılavuzu](MODEL_EGITIMI.md)
- [Proje Analiz Raporu](PROJE_ANALIZ_RAPORU.md)

## 🤝 Katkıda Bulunma

Katkılarınızı bekliyoruz! Lütfen önce bir issue açın veya pull request gönderin.

## 📄 Lisans

Bu proje MIT lisansı altında lisanslanmıştır. Detaylar için [LICENSE](LICENSE) dosyasına bakın.

## 👨‍💻 Geliştirici

Bilal Elmas

## 🙏 Teşekkürler

- Apple Vision Framework
- Firebase
- SwiftUI Community

---

⭐ Beğendiyseniz yıldız vermeyi unutmayın!

