# Android Release Build Malva

Malva Android sekarang memakai production package name:

```text
id.malva.app
```

Gunakan package name ini saat membuat Android app di Firebase. Jangan lagi
pakai package development `com.example.malva_mental_health`.

## Build debug lokal

```bash
flutter build apk --debug --dart-define=MALVA_API_BASE_URL=http://10.0.2.2:8080
```

## Build debug ke API production/staging

```bash
flutter build apk --debug --dart-define=MALVA_API_BASE_URL=https://api.malva.id
```

## Siapkan release keystore

Buat keystore lokal. Contoh:

```bash
keytool -genkeypair \
  -v \
  -keystore android/malva-release-key.jks \
  -storetype JKS \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias malva
```

Copy template:

```bash
cp android/key.properties.example android/key.properties
```

Isi `android/key.properties` sesuai password dan path keystore:

```properties
storePassword=...
keyPassword=...
keyAlias=malva
storeFile=malva-release-key.jks
```

File berikut tidak boleh di-commit:

```text
android/key.properties
android/*.jks
android/*.keystore
```

## Build release APK

```bash
flutter build apk --release --dart-define=MALVA_API_BASE_URL=https://api.malva.id
```

## Build release AAB

Untuk Play Store, format yang umum dipakai adalah AAB:

```bash
flutter build appbundle --release --dart-define=MALVA_API_BASE_URL=https://api.malva.id
```

## Checklist sebelum release

- [ ] Android package name sudah `id.malva.app`.
- [ ] Firebase Android app dibuat dengan package `id.malva.app`.
- [ ] `android/app/google-services.json` sesuai package production.
- [ ] `android/key.properties` ada di mesin build, tapi tidak di repo.
- [ ] Keystore `.jks` disimpan aman dan dibackup.
- [ ] `MALVA_API_BASE_URL` mengarah ke HTTPS production/staging.
- [ ] `flutter analyze` bersih.
- [ ] `flutter test` lulus.
- [ ] `flutter build apk --release ...` atau `flutter build appbundle --release ...` berhasil.
