# Build and install GeoGebra on an iPad

This repository includes an iPad app in `ios/GeoGebraIOS.xcodeproj`. Native UIKit navigation provides calculator selection, document import, construction export, and a live Guided Access status indicator. GeoGebra's Java/GWT engine and mathematical UI still execute in a bundled `WKWebView`; this is an incremental iOS integration, not a completed native rewrite or a feature-equivalent replacement for the official iOS app.

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

The native **Prüfung** menu integrates the GeoGebra engine's exam lifecycle with iPadOS. Rebuild the web assets after updating: the integration requires the new `IOSExamBridge` compiled into the engine.

1. Export your current construction. Choose **Prüfung > Prüfung vorbereiten**; this reloads Calculator Suite with its exam start dialog.
2. The app requests `UIAccessibility.requestGuidedAccessSession(enabled: true)`. Automatic locking requires a supervised iPad with an MDM profile allowing this app's bundle identifier to enter Autonomous Single App Mode. An ordinary Personal Team installation does not provide that permission. If iPadOS refuses, manually enable Guided Access and select **Prüfung vorbereiten** again.
3. Confirm Start in GeoGebra. The engine checks the native lock confirmation before starting. The native banner distinguishes preparation, an active exam, and an interrupted exam. Native calculator switching, file import/export, external navigation, and the debug shortcut are blocked during the session.
4. Finish and exit using GeoGebra's exam UI. Its `IDLE` transition ends the native session. If the app acquired the lock automatically, it requests automatic release. A manually activated lock must be ended by its owner with the device passcode.

**Prüfung > Protokoll anzeigen** shows timestamped engine state changes, app deactivation/return, lock loss, and blocked external actions. The native record is stored in app preferences across launches, separately from GeoGebra's exam summary. It is a local diagnostic record, not tamper-proof certification. App deactivation or loss of the lock leaves a persistent interrupted indicator even after returning. The engine's existing web exam logging remains enabled.

After the app or web process terminates, the native record is recovered and marked interrupted. It does **not** silently restart the previous engine exam, restore its in-memory constructions, or recreate a continuous timer. Close the interrupted session through the protocol before starting a new one. Full construction/timer recovery after process termination is not implemented. Mac Catalyst can test the app UI, but a locked exam requires a physical iPad. Guided Access does not itself disable Wi-Fi; this implementation does not change network settings.

Run `node --test ios/tests/exam-bridge.test.cjs` to check the host/engine message contract. Before relying on the integration, build in Xcode and test both an ordinary iPad (automatic lock denied, manual fallback) and a supervised allowlisted iPad (automatic lock and release). Verify lock loss, app interruption, process termination, relaunch, and finishing the exam from GeoGebra's summary. The integration has not yet been compiled or device-tested in this Linux workspace.

For testing app switching, a **Debug** build accepts `Skibidi` followed by Enter in a GeoGebra input field. With Guided Access off, the first entry records the time, shows a persistent **TESTBUILD** banner, and opens Safari (or the default browser on Mac). Return to GeoGebra manually and enter `Skibidi` again to record the return. With Guided Access on, iPadOS blocks app switching; the test command displays a message instead of attempting to disable it. These test events are stored separately in the app's preferences; they do not change GeoGebra's exam state, restore an iPad lock, or certify a continuous exam. Release builds do not include this shortcut.

## Using files

- To open a construction, use GeoGebra's **Open** action or tap a `.ggb` file in the Files app and choose GeoGebra.
- To save or export, choose GeoGebra's save/export action. The iOS share sheet lets you save to Files, AirDrop, or send the result to another app.
- The math engine and primary UI are bundled and can start offline. Online materials, sign-in, and other cloud features still require internet access.

## Changing the included calculator

The app starts Calculator Suite. Use the native **Rechner** menu to select Suite, Classic, Graphing, Geometry, CAS, 3D, or Scientific. Export your construction before switching; switching reloads the engine. The native **Öffnen** button opens the Files picker, and **Export** creates a `.ggb` construction through the engine API and presents the share sheet. The lock icon reports Guided Access status on iPad; tap it for setup instructions. Mac Catalyst shows an information icon because Guided Access is unavailable on macOS.

## Implementation status

The integration requests Autonomous Single App Mode on supported managed devices; the required supervision and MDM allowlist cannot be supplied by adding an Xcode setting. Native math rendering, a native CAS engine, verified account sign-in, complete crash recovery, and full parity with the official app remain outstanding. Full native parity requires porting or replacing the Java/GWT rendering and platform adapters and testing the result against the official app on Apple hardware.

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
