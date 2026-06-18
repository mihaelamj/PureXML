# UIKit Views

How a Tiledown-style native editor writes its UIKit renderer: `UIViewController` and
`UIView` subclasses that are purely presentational over the framework-free model
(see `pre-ui-layer.md`). The renderer reads Surface values, forwards every user
action as `perform(_ intent:)`, and re-renders on the model's change signal. It
holds ZERO business logic and owns ZERO state that is not view-local.

## Core rules

1. The renderer renders Surface state only: no business logic, no API calls, no domain decisions.
2. Every user action becomes a `perform(_ intent:)` call; the renderer reports, it never decides.
3. Observe the model's `Set<SurfaceArea>` change signal and re-pull the dirty areas; UIKit is not reactive, so drive updates from the signal, never from ad hoc mutation.
4. All layout in code (Auto Layout or manual `layoutSubviews`); no Storyboards, no XIBs.
5. Use a diffable data source for any list or grid, keyed by stable Surface identifiers.
6. Every interactive element has an `accessibilityLabel` (and a hint where the action is non-obvious).
7. The one place appearance happens is a single `color(for: token)` map; never hard-code a `UIColor` inline.
8. Reuse cells; never stash per-row state on a cell, it will be recycled.

## Decision tree: code belongs in the UIKit renderer?

```
Visual presentation (views, layout, animation) → YES
View-local UI state (in-flight gesture, scroll offset) → YES
Reading a Surface to populate views → YES
Translating a tap/swipe/edit into an Intent → YES (perform(intent))
Data transformation → NO (domain service, in the model)
Business logic, validation, enable/disable decision → NO (engine; reflect the surface flag)
Navigation decision → NO (engine sets a destination surface; the controller reflects it)
Network / persistence → NO (data layer, behind a seam)
```

## Patterns

### Binding the model and re-pulling on the signal

```swift
final class TileListViewController: UIViewController {
    private let model: TileListRendererModel   // pull slices + perform(_:) + change signal
    private lazy var dataSource = makeDataSource()

    init(model: TileListRendererModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("code-only UI") }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()              // all layout in code
        model.onChange = { [weak self] dirty in
            self?.apply(dirty)            // re-pull only the dirty surface areas
        }
        model.perform(.appWillAppear)     // lifecycle is an intent, not controller logic
    }

    private func apply(_ dirty: Set<SurfaceArea>) {
        if dirty.contains(.list) { applyListSnapshot(model.listSurface) }
        if dirty.contains(.status) { statusLabel.text = model.statusSurface.message }
    }
}
```

### User action to Intent (never a decision in the controller)

```swift
// CORRECT: report the intent, the re-pull happens via the change signal
@objc private func didTapReload() {
    model.perform(.run(.reload))
}

func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
    model.perform(.select(id))
}

// INCORRECT: business logic in the renderer
@objc private func badReload() {
    Task { try? await RenderService.shared.reload() }   // wrong layer, wrong everything
}
```

### Lists via a diffable data source, keyed by Surface IDs

```swift
private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, SurfaceID> {
    let cell = UICollectionView.CellRegistration<TileCell, SurfaceID> { [model] cell, _, id in
        cell.render(model.tileSurface(id))    // cell reflects a surface, owns no state
    }
    return .init(collectionView: collectionView) { cv, indexPath, id in
        cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
    }
}

private func applyListSnapshot(_ surface: ListSurface) {
    var snapshot = NSDiffableDataSourceSnapshot<Section, SurfaceID>()
    snapshot.appendSections([.main])
    snapshot.appendItems(surface.orderedIDs, toSection: .main)
    dataSource.apply(snapshot, animatingDifferences: true)
}
```

### Enable/disable reflects a surface flag (the engine decides)

```swift
// The engine computes whether the action is allowed; the renderer only reflects it.
reloadButton.isEnabled = model.toolbarSurface.isReloadEnabled
```

### Navigation reflects a destination surface

```swift
private func apply(_ dirty: Set<SurfaceArea>) {
    guard dirty.contains(.navigation) else { return }
    switch model.navigationSurface.destination {
    case .none:
        if presentedViewController != nil { dismiss(animated: true) }
    case .detail(let detail):
        present(TileDetailViewController(model: detail), animated: true)
    }
}
```

### Accessibility

```swift
reloadButton.accessibilityLabel = "Reload tiles"
reloadButton.accessibilityHint = "Fetches the latest tiles"
```

## Observing the change signal

UIKit has no built-in reactivity, so the renderer is driven by the model's `Notify`
signal, never by mutating views from wherever an event lands:

- **Re-pull loop (default).** The model calls back with a `Set<SurfaceArea>`; the
  controller re-pulls only those areas and updates the corresponding views. Coalesce
  rapid signals to the next runloop tick to avoid redundant layout.
- **Observation bridge (optional).** If the model exposes `@Observable` surfaces,
  wrap reads in `withObservationTracking`, re-registering after each callback, and
  funnel the callback into `setNeedsUpdate`-style invalidation. It is still a
  re-pull; Observation only schedules it.

Mutation flows one way: intent in, surface out, re-pull. Never mutate a view from a
place that also mutates the model.

## Identity and reuse (the UIKit trap)

Cells and reusable views are recycled; treat each as a pure function of the surface
it renders.

- A cell MUST fully reconfigure from its surface in `render(_:)`; never assume residual state from a prior row.
- Cancel any in-flight async (an image load) in `prepareForReuse`.
- Drive list identity from stable `SurfaceID`s in the diffable snapshot, never from index paths.
- Keep view-local values (a half-finished gesture) on the view, never in the model, and never let them survive reuse.

## App setup (no storyboard, no XIB)

UI is created in code, always. A code-only UIKit app removes the storyboard
scaffolding the template ships with:

- Delete the **Main storyboard** entry: clear "Main storyboard file base name"
  (`UIMainStoryboardFile`) and, under the scene manifest, the
  `UISceneStoryboardFile` reference in Info.plist; remove `Main.storyboard` and any
  `.xib`.
- Create the window and root view controller in code, in the scene delegate
  (`scene(_:willConnectTo:)` builds the `UIWindow`, sets `rootViewController`, and
  calls `makeKeyAndVisible()`), or in the app delegate for a single-scene app.
- Set `UILaunchScreen` as an empty dictionary in Info.plist (a code-only launch
  screen) rather than pointing at a launch storyboard.

## Validation checklist

- [ ] Zero business logic; every decision reflects a surface the engine set
- [ ] Every user action forwarded as `perform(_ intent:)`
- [ ] Updates driven by the `Set<SurfaceArea>` change signal, not ad hoc mutation
- [ ] All layout in code; no Storyboards or XIBs
- [ ] Lists use a diffable data source keyed by stable Surface IDs
- [ ] Cells reconfigure fully on reuse; async cancelled in `prepareForReuse`
- [ ] Accessibility labels on every interactive element
- [ ] Appearance only through the `color(for:)` map
- [ ] This is one of several renderers over the same model (see `pre-ui-layer.md`)

## Companion rules

- `pre-ui-layer.md`: the framework-free model this renderer adapts; renderers are the only UI import, gated mechanically.
- `swiftui-views.md`, `appkit-views.md`: the sibling renderers over the same model; build all three and compare (see `../domain-first.md`).
- `view-models.md`: responsibilities of the presentation layer the renderer binds to.
- `colors.md`, `fonts.md`: the `color(for:)` and font sources the renderer reflects.
