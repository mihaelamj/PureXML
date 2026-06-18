# Page Object Model (for UI tests)

**Status: MANDATORY for UI tests.** A UI test interacts with a screen only through a page object, never through raw element queries. Each screen has one page object that owns its locators and its actions; the test body names pages and calls their methods, and never touches a `XCUIElement` or a raw identifier string. This keeps tests readable, keeps a UI change confined to one page object, and makes invalid navigation a compile error.

## The pieces

1. **A base page owns the mechanics.** A single shared base class is constructed with the `XCUIApplication` injected (`init(app:)`) and holds every reusable interaction: waiting for an element to appear or disappear, tapping, asserting existence, scrolling to an element, taking a screenshot. Every method threads `file: StaticString = #filePath, line: UInt = #line` so a failure blames the test's call site, not the base page. Methods are `open` so a page can override a wait without re-implementing it.

   A default identifier-driven XCUITest registry ships in `FlowSpecXCUI`, part of the [FlowSpec](https://github.com/mihaelamj/FlowSpec) package, so an app whose views set accessibility identifiers can run scenarios with no custom registry code; the page objects themselves are per-app. See `flowspec.md`.

2. **One page object per screen.** A concrete page subclasses the base class, file name equals page name. Its locators are computed `XCUIElement` properties that query the app by a shared identifier constant and the typed element kind (`app.buttons[ID.Catalog.search]`, `app.staticTexts[ID.Item.title]`), never a raw string. Its methods split into verifications (return `Self`) and actions (return the next page).

3. **A single source of truth for accessibility identifiers.** Identifiers live in one shared enum (one nested namespace per screen, `public static let` constants) in a package that BOTH the app and the UI tests depend on. The app sets them (`.accessibilityIdentifier(ID.Catalog.search)`); the page objects query the same constants. Renaming an identifier is one edit the compiler propagates to producer and consumer, so source and tests cannot drift into a string mismatch.

4. **Fluent, type-safe navigation.** An action returns the page it navigates to (`openItem() -> ItemPage`, `goBack() -> CatalogPage`); a verification returns `Self`. A test reads as a chain (`CatalogPage(app:).verifyShown().openItem().verifyShown()`), and the compiler rejects an impossible navigation path because the return types do not line up.

## DO

- Construct the first page with the app, then chain; let action methods return the next page.
- Put every locator behind a shared accessibility-identifier constant; the app sets it, the page queries it.
- Keep `XCUIElement` properties private on the page; expose screen actions, not elements.
- Wait explicitly (`waitForExistence(timeout:)` and predicate waits); never `sleep()`. See `../core/no-shortcuts-first-principles.md`.
- Thread `#filePath` / `#line` through waits and asserts so failures point at the test.
- One page object per screen; recurring mechanics live once in the base page.

## DON'T

- Do not query `app.buttons["raw string"]` in a test body; that is the coupling page objects exist to remove.
- Do not return `Void` from a navigation action; return the destination page so the type system checks the flow.
- Do not phrase a locator as a literal; route it through the shared identifier enum.
- Do not `sleep()` to dodge a race; wait for the element. A sleep is a silenced symptom.
- Do not duplicate wait or tap logic per page; it belongs in the base page.

## Acceptance check

A conforming UI test suite has: (1) a shared base class (constructed with the app) that owns waits, taps, and asserts, with `#filePath`/`#line` threaded through; (2) one page object per screen, file name equals page name, locators private and routed through a shared identifier enum; (3) a single accessibility-identifier source of truth in a package both the app and tests depend on, with the app setting and the tests querying the same constants; (4) action methods that return the next page and verification methods that return `Self`; (5) no raw element-query strings and no `XCUIElement` in any test body (grep the test target); (6) no `sleep()` anywhere in the page objects or tests. A suite that queries raw strings, or returns `Void` from navigation, or sleeps to avoid a race, fails this rule even if it currently passes.

## Companion rules

- `flowspec.md`: drive page objects from a declarative scenario corpus; the scenario step registry calls page-object actions.
- `pre-ui-layer.md`: the accessibility identifiers a page object queries should line up with the surface identities the model exposes, so a scenario can target the same element across renderers.
- `../core/no-shortcuts-first-principles.md`: the no-sleep, wait-explicitly discipline.
- `../core/testing-discipline.md`: real tests, on every change.
