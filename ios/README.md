# BrewPilot iOS app

SwiftUI, iOS 17+. Sources in `BrewPilot/`; the Xcode project is generated
from `project.yml` via xcodegen (see below).

## Project (xcodegen)

`project.yml` is the source of truth (committed); the generated `.xcodeproj`
is gitignored. Regenerate any time:

```bash
cd ios
xcodegen generate
open BrewPilot.xcodeproj
```

Bundle ID `com.felipemunoz.brewpilot` (must be globally unique for device
signing; change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` if you prefer
another), iOS 17+, camera + bluetooth usage strings included.
Simulator build needs no signing:

```bash
xcodebuild -project BrewPilot.xcodeproj -scheme BrewPilot \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

Device: add your Apple ID in Xcode → Settings → Accounts, select Team +
automatic signing, then run on your iPhone (same Wi-Fi as the proxy).
First launch needs a manual trust: iPhone Settings → General →
VPN & Device Management → Developer App → Trust. CLI equivalent:

```bash
xcodebuild -project BrewPilot.xcodeproj -scheme BrewPilot \
  -destination 'platform=iOS,name=<tu iPhone>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> \
  ~/Library/Developer/Xcode/DerivedData/BrewPilot-*/Build/Products/Debug-iphoneos/BrewPilot.app
xcrun devicectl device process launch --device <UDID> com.felipemunoz.brewpilot
```

## Architecture

- `BrewStateMachine.swift` — deterministic phases, guard rails, flow math. No AI here.
- `ScaleBLEManager.swift` — CoreBluetooth central, SPEC §7 GATT profile.
- `CameraManager.swift` — 720p capture, 1-deep buffer, event-only uploads.
- `ProxyClient.swift` — HTTPS to the proxy; no API keys on device.
- Views: `ConnectView`, `RecipeView`, `BrewView`, `ReportView` (TabView skeleton;
  guided flow lands day 4).

`ProxyClient.baseURL` defaults to the production Modal proxy. For local dev,
point it at your Mac's LAN IP (`uvicorn server.app:app`, same Wi-Fi);
the simulator can use `http://127.0.0.1:8000`.
