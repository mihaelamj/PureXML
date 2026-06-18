# App Target Structure

Three patterns for the app entry point: SwiftUI (minimal App shell), UIKit (SceneDelegate), AppKit (NSApplicationDelegate).

**Reference layouts:**
- SwiftUI pattern: `Apps/iosApp/`, `Apps/macApp/` (one Xcode project per platform under `Apps/`)
- UIKit/AppKit pattern: `Apps/App/UIKitApp/`, `Apps/App/AppKitApp/` (siblings under a single project)

### Pattern 1: SwiftUI Apps (Minimal App Shell)

SwiftUI app targets MUST be minimal shells that import a feature package and display a view.

#### iOS App Target (iosApp or iOSApp)

```swift
// Apps/iosApp/iosApp/iosAppApp.swift
import AppFeature  // ← Import the feature package
import SwiftUI

@main
struct iosAppApp: App {
    var body: some Scene {
        WindowGroup {
            AppView()  // ← Use the view from the feature package
        }
    }
}
```

#### macOS App Target (macApp)

```swift
// Apps/macApp/macApp/macAppApp.swift
import AppFeature  // ← Same feature package as iOS
import SwiftUI

@main
struct macAppApp: App {
    var body: some Scene {
        WindowGroup {
            AppView()  // ← Same view as iOS
        }
    }
}
```

**Directory Structure:**
```
Apps/
├── iosApp/
│   └── iosApp/
│       ├── iosAppApp.swift        # Minimal: import + AppView()
│       └── Assets.xcassets/
├── macApp/
│   └── macApp/
│       ├── macAppApp.swift        # Minimal: import + AppView()
│       └── Assets.xcassets/
```

Rules:
1. App targets contain only the `@main` struct, `import AppFeature`, and `AppView()`.
2. All UI logic lives in the feature package (e.g. `AppFeature`).
3. Both iOS and macOS targets use the same feature package.
4. The feature package exports `AppView` (a SwiftUI `View`).
5. Font registration (if needed) goes in `init()` before body

#### Font Registration in SwiftUI App

```swift
// Apps/iosApp/iosApp/iosAppApp.swift
import AppFeature
import AppFont  // ← Import font package
import SwiftUI

@main
struct iosAppApp: App {
    init() {
        FontRegistration.registerFonts()  // ← Register before UI
    }

    var body: some Scene {
        WindowGroup {
            AppView()
        }
    }
}
```

---

### Pattern 2: UIKit Apps (iOS - SceneDelegate Pattern)

UIKit app targets MUST delegate to a feature package for window creation.

**Reference layout:** `Apps/App/UIKitApp/`

#### AppDelegate.swift

```swift
// Apps/UIKitApp/AppDelegate.swift
import UIKit

@main
@MainActor
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        true
    }

    // MARK: UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
```

#### SceneDelegate.swift

```swift
// Apps/UIKitApp/SceneDelegate.swift
import CanvasFeature  // ← Import the feature package (NOT "Canvas")
import UIKit

@MainActor
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        window = CanvasFeature.createMainWindow(for: windowScene)  // ← Factory from feature
    }
}
```

**Directory Structure:**
```
Apps/
└── UIKitApp/
    ├── AppDelegate.swift     # Minimal lifecycle
    ├── SceneDelegate.swift   # Import CanvasFeature, create window
    ├── Info.plist
    └── Assets.xcassets/
```

Rules:
1. AppDelegate handles only app lifecycle (minimal code).
2. SceneDelegate imports the feature package.
3. Feature package provides `createMainWindow(for:)` factory function.
4. Feature package name ends with `Feature` (e.g. `CanvasFeature`, not `Canvas`).

---

### Pattern 3: AppKit Apps (macOS - NSApplicationDelegate Pattern)

AppKit app targets MUST delegate to a feature package, with menu code in a SEPARATE file.

**Reference layout:** `Apps/App/AppKitApp/`

#### main.swift

```swift
// Apps/AppKitApp/main.swift
import Cocoa

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
}
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
```

#### AppDelegate.swift

```swift
// Apps/AppKitApp/AppDelegate.swift
import CanvasFeature  // ← Import the feature package (NOT "Canvas")
import Cocoa

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: NSWindowController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupMainMenu()  // ← Separate file for menus
        windowController = CanvasFeature.createWindowController()  // ← Factory from feature
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ aNotification: Notification) {}

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
```

#### MainMenu.swift (SEPARATE FILE)

```swift
// Apps/AppKitApp/MainMenu.swift
import Cocoa

extension AppDelegate {
    func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About MyApp", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide MyApp", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit MyApp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "New", action: #selector(newDocument(_:)), keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "Open...", action: #selector(openDocument(_:)), keyEquivalent: "o"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))

        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Actions

    @objc func newDocument(_ sender: Any?) {
        // TODO: Create new document
    }

    @objc func openDocument(_ sender: Any?) {
        // TODO: Open document
    }
}
```

**Directory Structure:**
```
Apps/
└── AppKitApp/
    ├── main.swift           # NSApplicationMain setup
    ├── AppDelegate.swift    # Import CanvasFeature, create window
    ├── MainMenu.swift       # Separate file for menu code (extension)
    ├── Info.plist
    └── Assets.xcassets/
```

Rules:
1. AppKit uses `main.swift` + `AppDelegate.swift` (no `@main` on AppDelegate).
2. Menu code lives in a separate file (`MainMenu.swift`).
3. Menu code is an extension of `AppDelegate`.
4. Feature package provides `createWindowController()` factory function.
5. Feature package name MUST end with `Feature` (e.g., `CanvasFeature`, NOT `Canvas`)

---

### Feature Package Exports

The feature package (e.g., `AppFeature`, `CanvasFeature`) MUST export:

#### For SwiftUI

```swift
// Packages/Sources/AppFeature/AppView.swift
import SwiftUI

public struct AppView: View {
    public init() {}

    public var body: some View {
        // App content
    }
}
```

#### For UIKit

```swift
// Packages/Sources/CanvasFeature/WindowFactory.swift
import UIKit

public enum CanvasFeature {
    @MainActor
    public static func createMainWindow(for windowScene: UIWindowScene) -> UIWindow {
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = MainViewController()
        window.makeKeyAndVisible()
        return window
    }
}
```

#### For AppKit

```swift
// Packages/Sources/CanvasFeature/WindowFactory.swift
import AppKit

public enum CanvasFeature {
    @MainActor
    public static func createWindowController() -> NSWindowController {
        let viewController = MainViewController()
        let window = NSWindow(contentViewController: viewController)
        window.title = "MyApp"
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.center()
        return NSWindowController(window: window)
    }
}
```

---

### App Target Checklist

- [ ] SwiftUI: App file has ONLY `import FeaturePackage` + `FeatureView()`
- [ ] SwiftUI: Both iOS and macOS use the SAME feature package
- [ ] UIKit: SceneDelegate imports feature package and uses factory
- [ ] AppKit: AppDelegate imports feature package and uses factory
- [ ] AppKit: Menu code is in SEPARATE `MainMenu.swift` file
- [ ] AppKit: `main.swift` exists with `NSApplicationMain`
- [ ] Feature package name ends with `Feature` (NOT raw name like `Canvas`)
- [ ] Feature package exports appropriate factory functions
- [ ] Font registration (if needed) happens in app init BEFORE UI

