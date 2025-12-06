# Model Eğitimi Kılavuzu

## 📚 Genel Bakış

Smart Invoice uygulaması **Active Learning** mekanizması kullanarak kullanıcı düzeltmelerinden öğrenir ve zamanla daha iyi OCR sonuçları üretir.

## 🔄 Nasıl Çalışır?

### 1. Otomatik Veri Toplama

Kullanıcı bir faturayı taradığında ve OCR sonuçlarını düzelttiğinde:

1. **Orijinal OCR Sonucu** kaydedilir
2. **Kullanıcı Düzeltmeleri** kaydedilir
3. **Farklar (diffs)** otomatik tespit edilir
4. **TrainingData** Firebase'e kaydedilir

```swift
// Otomatik olarak InvoiceViewModel.saveInvoice() içinde çalışır
if let original = originalOCRInvoice {
    let diffs = TrainingData.detectDiffs(original: original, final: invoice)
    if !diffs.isEmpty {
        let trainingData = TrainingData(
            invoiceId: invoiceId,
            originalOCR: original,
            userCorrected: invoice,
            diffs: diffs
        )
        try? await repository.addTrainingData(trainingData)
    }
}
```

### 2. Model Analizi

`ModelTrainingService` ile toplanan veriler analiz edilir:

- **Hangi alanlar en çok hata yapıyor?** (merchantName, totalAmount, vb.)
- **Hangi pattern'ler iyileştirilmeli?**
- **Confidence score'lar nasıl ayarlanmalı?**

### 3. İyileştirme Önerileri

Sistem şu önerileri üretir:

- **Yeni regex pattern'leri**
- **Anahtar kelime önerileri**
- **Confidence threshold ayarlamaları**

## 🛠️ Kullanım

### ModelTrainingView ile Analiz

1. **Profil** sekmesine gidin
2. **Model Eğitimi** bölümüne tıklayın
3. **"Analiz Et"** butonuna basın
4. Sonuçları inceleyin:
   - Hata dağılımı grafiği
   - Pattern önerileri
   - Confidence ayarlamaları

### CSV Export

Python backend ile model eğitimi için:

1. **Model Eğitimi** ekranında **"CSV Olarak Dışa Aktar"** butonuna basın
2. CSV dosyasını indirin
3. Python script'inizde kullanın:

```python
import pandas as pd

# CSV'yi oku
df = pd.read_csv('training_data.csv')

# Her alan için model eğitimi
for field in df['field'].unique():
    field_data = df[df['field'] == field]
    # Model eğitimi yap
    train_model(field_data)
```

## 📊 Veri Yapısı

### TrainingData Modeli

```swift
struct TrainingData {
    var invoiceId: String
    var originalOCR: Invoice      // OCR'ın ilk bulduğu
    var userCorrected: Invoice    // Kullanıcının düzelttiği
    var diffs: [String]           // Değişen alanlar
    var createdAt: Date
}
```

### CSV Formatı

```csv
invoice_id,field,original_value,corrected_value,diff_type,created_at
abc123,merchantName,"Yanlış Firma","Doğru Firma",merchantName,2025-01-27
abc123,totalAmount,100.0,150.0,totalAmount,2025-01-27
```

## 🎯 İyileştirme Stratejileri

### 1. Regex Pattern İyileştirmesi

**Sorun:** `totalAmount` alanında yıl (2024) ile tutar karışıyor.

**Çözüm:** `RegexPatterns.swift` dosyasında pattern'i güncelleyin:

```swift
// Önce
static let flexible = "\\b\\d{1,3}(?:\\.\\d{3})*(?:[.,]\\d{1,2})?\\s*(?:TL|₺)?\\b"

// Sonra (yıl kontrolü ekle)
static let flexible = "\\b\\d{1,3}(?:\\.\\d{3})*(?:[.,]\\d{1,2})?\\s*(?:TL|₺)?\\b(?<!202[0-9])"
```

### 2. Anahtar Kelime Ekleme

**Sorun:** Yeni bir fatura formatı tespit edildi.

**Çözüm:** `RegexPatterns.Keywords` içine yeni kelimeler ekleyin:

```swift
static let payableAmounts = [
    "ÖDENECEK", 
    "GENEL TOPLAM",
    "YENİ FORMAT TUTAR"  // Yeni eklenen
]
```

### 3. Confidence Score Ayarlama

**Sorun:** Bir alan çok hata yapıyor.

**Çözüm:** `InvoiceParser` içinde confidence threshold'u düşürün:

```swift
// Eğer confidence düşükse, daha fazla kontrol yap
if block.confidence < 0.7 {
    // Ekstra validasyon
}
```

## 🔬 Python Backend ile Model Eğitimi

### 1. Veri Hazırlama

```python
import pandas as pd
from sklearn.model_selection import train_test_split

# CSV'yi oku
df = pd.read_csv('training_data.csv')

# Her alan için ayrı dataset
for field in ['merchantName', 'totalAmount', 'taxAmount']:
    field_df = df[df['field'] == field]
    
    # Train/test split
    train, test = train_test_split(field_df, test_size=0.2)
    
    # Model eğitimi
    model = train_model(train)
    
    # Test
    accuracy = evaluate_model(model, test)
    print(f"{field} accuracy: {accuracy}")
```

### 2. Core ML Model Eğitimi

```python
import coremltools as ct
from sklearn.ensemble import RandomForestClassifier

# Model eğitimi
model = RandomForestClassifier()
model.fit(X_train, y_train)

# Core ML'e dönüştür
coreml_model = ct.converters.sklearn.convert(
    model,
    input_features=['text_features'],
    output_feature_names='prediction'
)

# Kaydet
coreml_model.save('InvoiceParser.mlmodel')
```

### 3. Model Deployment

1. Eğitilmiş `.mlmodel` dosyasını Xcode projesine ekleyin
2. `InvoiceParser` içinde kullanın:

```swift
import CoreML

let model = try InvoiceParserMLModel()
let prediction = try model.prediction(input: textFeatures)
```

## 📈 Metrikler

### Başarı Kriterleri

- **Accuracy:** %95+ doğru çıkarım
- **Precision:** Yanlış pozitif oranı < %5
- **Recall:** Eksik çıkarım oranı < %5

### İzleme

`ModelTrainingView` ekranında:

- Toplam örnek sayısı
- Hata dağılımı
- Pattern önerileri
- Confidence ayarlamaları

## 🚀 Gelecek Geliştirmeler

1. **Otomatik Pattern Güncelleme:** Önerileri otomatik uygula
2. **A/B Testing:** Farklı pattern'leri test et
3. **Real-time Learning:** Model güncellemelerini anında uygula
4. **Federated Learning:** Kullanıcı gizliliğini koruyarak öğren

## 📝 Notlar

- Training data Firebase'de `training_data` koleksiyonunda saklanır
- Her kullanıcı düzeltmesi otomatik olarak kaydedilir
- Veriler anonimleştirilebilir (GDPR uyumluluğu için)
- Model eğitimi opsiyoneldir - sistem olmadan da çalışır

---

**Son Güncelleme:** 2025-01-27  
**Versiyon:** 1.0


