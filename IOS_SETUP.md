# Build and install GeoGebra on an iPad

This repository now includes an iPad app in `ios/GeoGebraIOS.xcodeproj`. It embeds the repository's compiled web application in a native `WKWebView`, preserving GeoGebra's iOS touch and keyboard support. The native shell also supports opening `.ggb` files from the Files app and exporting constructions or images through the iOS share sheet.

## Requirements

- A Mac with Xcode 13.3 or newer. The project is deliberately compatible with macOS 12.3 and Xcode 13.3.
- A full JDK 17 or newer (`java -version` and `javac -version` must both work; a JRE alone is not enough)
- An iPad running iPadOS 15 or newer
- A USB cable for the first installation, or wireless device deployment configured in Xcode
- An Apple ID added to Xcode

The first web build downloads Gradle and project dependencies and can take several minutes. It also requires several gigabytes of free memory and disk space.

> **Device-version note:** Xcode must include support for the iPadOS version installed on your physical iPad. Xcode 13.3 can build this project, run its iPad simulator, and deploy to iPadOS 15.x devices, but it cannot deploy to much newer iPadOS releases. If your iPad has a newer OS than Xcode supports, update macOS and Xcode before physical-device installation.

## 1. Build the web assets

Open Terminal, change to this repository's root, and run:

```bash
chmod +x ios/scripts/prepare_web_assets.sh
./ios/scripts/prepare_web_assets.sh
```

The script compiles the production GWT target, creates the offline Graphing Calculator page, and copies the result into the Xcode app bundle. Run it again whenever you change Java, GWT, HTML, JavaScript, or CSS source.

If Gradle reports an out-of-memory error, close memory-heavy applications and try again. The repository already configures the web compiler with a 4 GB heap.

## 2. Configure signing in Xcode

1. Open `ios/GeoGebraIOS.xcodeproj` in Xcode.
2. Select the **GeoGebraIOS** project, then the **GeoGebraIOS** target.
3. Open **Signing & Capabilities**.
4. Leave **Automatically manage signing** enabled.
5. Choose your Apple ID's **Team**.
6. If Xcode says the bundle identifier is unavailable, replace `org.geogebra.community.ios` with a unique value, such as `com.yourname.geogebra`.

No paid Apple Developer membership is required for installing on your own iPad. Apps signed with a free Personal Team normally expire after seven days and then need to be installed again. A paid membership provides longer-lived signing and is required for App Store or TestFlight distribution.

## 3. Install on the iPad

1. Connect the unlocked iPad to the Mac and tap **Trust** if prompted.
2. In Xcode's device selector, choose your iPad rather than a simulator.
3. Press **Run** (the triangle button) or use **Product > Run**.
4. If iPadOS asks for Developer Mode, open **Settings > Privacy & Security > Developer Mode**, enable it, restart the iPad, and confirm. Then run from Xcode again.
5. If the app is reported as an untrusted developer, open **Settings > General > VPN & Device Management**, select your developer identity, and trust it.

After Xcode finishes, GeoGebra appears on the Home Screen like any other app.

## Test on the Mac first

The target supports Mac Catalyst. In Xcode's device selector, choose **My Mac (Mac Catalyst)** and press **Run**. This launches the same UIKit/WKWebView shell directly on macOS 12.3. You can also select an iPad simulator included with Xcode to test the actual iPad layout before connecting a device.

## Exam mode

GeoGebra's official iOS apps can use iPadOS Guided Access or supervised Single App Mode to keep the user inside the app during an exam. This fork's `WKWebView` wrapper does not currently integrate those native controls and has not been certified for supervised exams. The browser version may require Safe Exam Browser to start an exam. Do not treat a running timer in this wrapper as proof that the device stayed in exam mode. For a real exam, use an approved GeoGebra exam app or a supervised setup required by the institution. Leave exam mode using its visible **Exit Exam** action; this ends the exam and records the exit in its protocol.

For testing app switching, a **Debug** build accepts `Skibidi` followed by Enter in a GeoGebra input field. With Guided Access off, the first entry records the time, shows a persistent **TESTBUILD** banner, and opens Safari (or the default browser on Mac). Return to GeoGebra manually and enter `Skibidi` again to record the return. With Guided Access on, iPadOS blocks app switching; the test command displays a message instead of attempting to disable it. These test events are stored separately in the app's preferences; they do not change GeoGebra's exam state, restore an iPad lock, or certify a continuous exam. Release builds do not include this shortcut.

## Using files

- To open a construction, use GeoGebra's **Open** action or tap a `.ggb` file in the Files app and choose GeoGebra.
- To save or export, choose GeoGebra's save/export action. The iOS share sheet lets you save to Files, AirDrop, or send the result to another app.
- The math engine and primary UI are bundled and can start offline. Online materials, sign-in, and other cloud features still require internet access.

## Changing the included calculator

The app starts `graphing-offline.html`. To use a different generated app, change `graphing-offline` in `loadGeoGebra()` inside `ios/GeoGebraIOS/GeoGebraViewController.swift`. Available generated entry points include `suite-offline`, `geometry-offline`, `cas-offline`, `3d-offline`, and `classic-offline`.

## Troubleshooting

### The app says “Web assets not built”

Run `./ios/scripts/prepare_web_assets.sh` from the repository root, then in Xcode choose **Product > Clean Build Folder** and run again.

### Xcode cannot create a provisioning profile

Confirm that an Apple ID is listed under **Xcode > Settings > Accounts**, select its team under **Signing & Capabilities**, and use a bundle identifier unique to you.

### Gradle cannot download dependencies

Confirm the Mac has internet access and that Java can reach HTTPS sites. A corporate proxy may need to be configured in `~/.gradle/gradle.properties`.

### A web feature opens Safari

Normal links intentionally open in Safari. GeoGebra itself remains in the app; its API requests and bundled assets continue to run in the embedded web view.

## Licensing

GeoGebra's source and trademarks have their own licensing conditions. Review <https://www.geogebra.org/license> before redistributing the app, especially for commercial use or public App Store distribution.
