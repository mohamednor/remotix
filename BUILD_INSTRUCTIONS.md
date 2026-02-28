# Remotix – Build Instructions

## Prerequisites

- Flutter SDK 3.22+ (stable channel)
- Android Studio + Android SDK (API 34)
- Xcode 15+ (for iOS)
- CocoaPods (`gem install cocoapods`)
- Java 17+

---

## 1. Project Setup

```bash
# Clone / copy the project folder, then:
cd remotix
flutter pub get
```

---

## 2. Android Build

### Debug APK
```bash
flutter build apk --debug
# Output: build/app/outputs/flutter-apk/app-debug.apk
```

### Release APK
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Release AAB (for Play Store)
```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

### Signing (required for release)
1. Generate keystore:
```bash
keytool -genkey -v -keystore remotix.keystore \
  -alias remotix -keyalg RSA -keysize 2048 -validity 10000
```

2. Create `android/key.properties`:
```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=remotix
storeFile=../remotix.keystore
```

3. Update `android/app/build.gradle` to reference the signing config.

---

## 3. iOS Build

### Install Pods
```bash
cd ios
pod install
cd ..
```

### Debug run
```bash
flutter run --debug
```

### Release build (Xcode required)
```bash
flutter build ios --release
```

Then open `ios/Runner.xcworkspace` in Xcode:
- Set signing team
- Set bundle identifier (e.g., `com.yourcompany.remotix`)
- Product → Archive → Distribute App

### IPA export
Use Xcode Organizer after archiving, or:
```bash
flutter build ipa --release
# Output: build/ios/ipa/remotix.ipa
```

---

## 4. iOS Capabilities Required

In Xcode → Runner target → Signing & Capabilities:
- ✅ Access WiFi Information
- ✅ Local Network (already in Info.plist)

---

## 5. AdMob Notes

- Production IDs are already embedded in the app
- No test device setup needed for production
- App ID: `ca-app-pub-4380269071153281~1338541200`
- Banner Unit: `ca-app-pub-4380269071153281/2984104871`
- Banner only appears on `RemoteControlScreen`

---

## 6. Project Structure

```
remotix/
├── pubspec.yaml
├── android/
│   ├── app/
│   │   ├── build.gradle
│   │   └── src/main/
│   │       ├── AndroidManifest.xml
│   │       └── res/values/
│   │           ├── styles.xml
│   │           └── colors.xml
│   ├── build.gradle
│   ├── settings.gradle
│   └── gradle.properties
├── ios/
│   └── Info.plist  ← merge into ios/Runner/Info.plist
└── lib/
    ├── main.dart
    ├── core/
    │   ├── constants/app_constants.dart
    │   ├── error/exceptions.dart
    │   ├── error/failures.dart
    │   ├── network/ssdp_discovery.dart
    │   └── utils/app_logger.dart
    ├── data/
    │   ├── models/device_model.dart
    │   └── repositories/device_repository_impl.dart
    ├── domain/
    │   ├── entities/device.dart
    │   ├── entities/tv_command.dart
    │   ├── repositories/device_repository.dart
    │   └── usecases/discover_devices_usecase.dart
    ├── drivers/
    │   ├── base/tv_driver.dart
    │   ├── base/driver_factory.dart
    │   ├── lg/lg_webos_driver.dart
    │   ├── samsung/samsung_tizen_driver.dart
    │   └── androidtv/android_tv_driver.dart
    └── presentation/
        ├── providers/device_provider.dart
        ├── screens/
        │   ├── splash_screen.dart
        │   ├── device_scan_screen.dart
        │   ├── device_list_screen.dart
        │   └── remote_control_screen.dart
        └── widgets/
            ├── remote_button.dart
            ├── dpad_widget.dart
            └── ad_banner_widget.dart
```

---

## 7. iOS Info.plist Integration

Copy the keys from `ios/Info.plist` into your existing `ios/Runner/Info.plist`:

```xml
<!-- AdMob -->
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-4380269071153281~1338541200</string>

<!-- Local Network -->
<key>NSLocalNetworkUsageDescription</key>
<string>Remotix needs local network access to find Smart TVs.</string>

<key>NSBonjourServices</key>
<array>
    <string>_http._tcp</string>
    <string>_googlecast._tcp</string>
</array>

<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

---

## 8. Troubleshooting

| Issue | Fix |
|---|---|
| `CHANGE_WIFI_MULTICAST_STATE` denied | Ensure WiFi connected, not hotspot |
| LG TV not pairing | Accept popup on TV screen |
| Samsung rejects connection | Enable "IP Control" in TV developer settings |
| AdMob no fill | Normal for new apps, wait 24-48h |
| iOS local network denied | User must allow in Settings → Privacy |
