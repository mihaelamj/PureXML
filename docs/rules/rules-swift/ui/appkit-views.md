# AppKit Views

How a Tiledown-style native editor writes its AppKit renderer: `NSViewController`
and `NSView` subclasses that are purely presentational over the framework-free
model (see `pre-ui-layer.md`). The renderer reads Surface values, forwards every
user action as `perform(_ intent:)`, and re-renders on the model's change signal,
observed through `withObservationTracking`. It holds ZERO business logic and owns
ZERO state that is not view-local.

## Core rules

1. The renderer renders Surface state only: no business logic, no API calls, no domain decisions.
2. Every user action (target/action, menu item, delegate callback) becomes a `perform(_ intent:)` call; the renderer reports, it never decides.
3. Observe the model with `withObservationTracking` (the AppKit idiom from `pre-ui-layer.md`), re-registering after each change, then re-pull the dirty `Set<SurfaceArea>`.
4. All layout and menus in code; no Storyboards, no XIBs, no `MainMenu.xib` (build `NSMenu` in the app delegate).
5. Use a diffable data source (`NSCollectionViewDiffableDataSource` / `NSTableViewDiffableDataSource`) keyed by stable Surface identifiers.
6. Every control sets an accessibility label (`setAccessibilityLabel(_:)`).
7. Appearance happens in one `color(for: token)` map returning `NSColor`; never hard-code inline.
8. AppKit views recycle (`makeView(withIdentifier:)`, `itemForRepresentedObjectAt:`); reconfigure fully, stash no per-row state.

## Decision tree: code belongs in the AppKit renderer?

```
Visual presentation (views, layout, animation) → YES
View-local UI state (drag in progress, split position) → YES
Reading a Surface to populate views → YES
Translating an action/menu/delegate callback into an Intent → YES (perform(intent))
Data transformation → NO (domain service, in the model)
Business logic, validation, enable/disable → NO (engine; reflect the surface flag)
Navigation / window routing decision → NO (engine sets a destination surface; the controller reflects it)
Network / persistence → NO (data layer, behind a seam)
```

## Patterns

### Entry point and menus in code

A code-only AppKit app has no storyboard and no `@main`, so the entry point is
`main.swift` and several steps the Xcode template normally hides must be written by
hand. This is the cumbersome part; you write it once per app.

```swift
// main.swift: AppKit with no storyboard needs an explicit entry point (no @main).
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)       // without this a tool-launched app has no dock icon or menu bar
app.mainMenu = buildMainMenu()          // programmatic NSMenu; there is no MainMenu.xib

let window = TileListWindow.make(model: model)
window.makeKeyAndOrderFront(nil)
model.perform(.appDidLaunch)            // lifecycle is an intent, not entry-point logic

app.activate()                          // bring the app to the front
app.run()
```

For lifecycle hooks (`applicationDidFinishLaunching`, termination) set an
`NSApplicationDelegate` via `app.delegate` before `run()`; keep it thin, it raises
intents and owns no behavior.

### Binding the model with withObservationTracking

```swift
final class TileListViewController: NSViewController {
    private let model: TileListRendererModel
    private lazy var dataSource = makeDataSource()

    init(model: TileListRendererModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("code-only UI") }

    override func loadView() { view = NSView() }        // all hierarchy built in code

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        observe()
    }

    // Re-register after every change: withObservationTracking fires once per registration.
    private func observe() {
        withObservationTracking {
            render(model.listSurface, model.statusSurface)
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observe() }
        }
    }
}
```

### Action / menu / delegate to Intent

```swift
// CORRECT: target/action reports an intent
@objc private func reload(_ sender: NSToolbarItem) {
    model.perform(.run(.reload))
}

// Menu validation reflects a surface flag the engine computed; it does not decide.
func validateMenuItem(_ item: NSMenuItem) -> Bool {
    model.menuSurface.isEnabled(item.action)
}

// NSTableView selection to intent
func tableViewSelectionDidChange(_ notification: Notification) {
    guard let id = dataSource.itemIdentifier(for: tableView.selectedRow) else { return }
    model.perform(.select(id))
}
```

### Lists via a diffable data source

```swift
private func makeDataSource() -> NSCollectionViewDiffableDataSource<Section, SurfaceID> {
    NSCollectionViewDiffableDataSource(collectionView: collectionView) { [model] cv, indexPath, id in
        let item = cv.makeItem(withIdentifier: .tile, for: indexPath) as! TileItem
        item.render(model.tileSurface(id))     // item reflects a surface, owns no state
        return item
    }
}

private func applyListSnapshot(_ surface: ListSurface) {
    var snapshot = NSDiffableDataSourceSnapshot<Section, SurfaceID>()
    snapshot.appendSections([.main])
    snapshot.appendItems(surface.orderedIDs, toSection: .main)
    dataSource.apply(snapshot, animatingDifferences: true)
}
```

### Navigation / windows reflect a destination surface

```swift
private func render(_ list: ListSurface, _ status: StatusSurface) {
    applyListSnapshot(list)
    statusLabel.stringValue = status.message
    switch model.navigationSurface.destination {
    case .none: detailWindow?.close()
    case .detail(let detail): presentDetail(detail)    // reflect, do not decide
    }
}
```

### Accessibility

```swift
reloadButton.setAccessibilityLabel("Reload tiles")
reloadButton.setAccessibilityHelp("Fetches the latest tiles")
```

## App setup (no storyboard, no XIB, and the network entitlement)

A code-only app drops the template scaffolding, so do by hand what the storyboard
did implicitly, and grant network access in the right place:

- **No storyboard, no XIB, no `MainMenu.xib`.** Remove the storyboard from the
  target and build both the window and the main menu in code
  (`app.mainMenu = buildMainMenu()`). UI is created in code, always.
- **`main.swift`, not `@main`.** With no `@NSApplicationMain` / `@main`, the entry
  point is `main.swift`: share the application, set the activation policy to
  `.regular`, install the menu, make the window key, `activate()`, then `run()`
  (see the entry-point pattern above).
- **Network access is an entitlement, not Info.plist.** If the app enables App
  Sandbox, network is denied by default. Grant it in the app's `.entitlements`
  file, which Xcode's "Signing & Capabilities → App Sandbox → Network" checkboxes
  write, never in Info.plist:

  ```xml
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>   <!-- outgoing: you make requests -->
  <true/>
  <key>com.apple.security.network.server</key>   <!-- incoming: you listen / accept -->
  <true/>
  ```

  `network.client` is outgoing, `network.server` is incoming; add only the
  direction the app actually uses. A non-sandboxed Mac app needs neither key.

## Responder chain (route, do not decide)

AppKit's responder chain is plumbing, not logic. A first-responder handler
translates the action into an intent and forwards it; it does not implement the
behavior.

- An `@objc` action reaching a controller via the responder chain calls `model.perform(...)` and returns; the engine owns what happens.
- Use `validateMenuItem` / `validateUserInterfaceItem` to reflect engine-computed enablement from a surface flag, never to compute it inline.
- Field-editor edits (`NSTextField` / `NSText`) forward each commit as an `.edit` intent over the document surface the model owns; the renderer keeps no separate copy of the text.

## Identity and reuse (the AppKit trap)

`NSTableView` / `NSCollectionView` recycle views and items; treat each as a pure
function of the surface it renders.

- An item/cell MUST fully reconfigure from its surface in `render(_:)`; never assume residual state.
- Cancel in-flight async in the reuse hook before the view is handed out again.
- Drive identity from stable `SurfaceID`s in the diffable snapshot, never from row indices.
- Keep view-local state (a drag in progress, a split-view position) on the view, never in the model.

## Validation checklist

- [ ] Zero business logic; every decision reflects a surface the engine set
- [ ] Every action/menu/delegate callback forwarded as `perform(_ intent:)`
- [ ] Updates driven by `withObservationTracking` re-registration over the change signal
- [ ] All layout and menus in code; no Storyboards, XIBs, or MainMenu.xib
- [ ] `main.swift` entry point (not `@main`) with `setActivationPolicy(.regular)` and `activate()`
- [ ] If sandboxed, network granted via `.entitlements` (`network.client` / `network.server`), not Info.plist
- [ ] Lists use a diffable data source keyed by stable Surface IDs
- [ ] Items/cells reconfigure fully on reuse; async cancelled before reuse
- [ ] Accessibility labels on every control
- [ ] Appearance only through the `color(for:)` map (`NSColor`)
- [ ] This is one of several renderers over the same model (see `pre-ui-layer.md`)

## Companion rules

- `pre-ui-layer.md`: the framework-free model this renderer adapts; AppKit observes the change signal via `withObservationTracking`.
- `swiftui-views.md`, `uikit-views.md`: the sibling renderers over the same model; build all three and compare (see `../domain-first.md`).
- `view-models.md`: responsibilities of the presentation layer the renderer binds to.
- `colors.md`, `fonts.md`: the `color(for:)` and font sources the renderer reflects.
