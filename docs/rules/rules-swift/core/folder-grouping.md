# Folder Grouping

How to lay out a source tree: one folder per unit of work, with file-grouping rules for the files inside that unit.

This is a cross-cutting layout rule. It is most concrete in package managers where one-folder-per-module is the default (Swift / SPM is the worked example below), but the same intent applies to any language's package tree, a web project tree, a docs tree, anywhere a tree of files exists. The principle is language-neutral: the filesystem boundary should mirror a semantic boundary, and every folder must answer "what is inside that is not outside?"

## One folder per buildable unit is the mandate, not just the default

For a package manager whose default is one folder per module (target, package, crate), the standing rule is: **every buildable unit maps to exactly one top-level source folder, and that folder is the unit's home** (`Sources/<Unit>/`, `Tests/<Unit>Tests/`). No single `path:` pointing many units into a shared parent, no disjoint `sources:` / `exclude:` slicing to carve multiple units out of one folder. Listing the source root must enumerate every unit; the filesystem boundary IS the unit boundary.

This supersedes the older "family-parent folder" idea for the unit-grouping case. The file-grouping rules below (grouping FILES *within* a single unit's folder) still apply unchanged. The two earned-exception patterns (same-kind single-file clusters; sub-units sharing an umbrella) are discouraged for new code; flatten unless there is a compelling, documented reason.

A migration that flattened a deep `Sources/{Core,Executables,...}/...` tree to strict one-folder-per-unit confirmed the payoff: a cluster of executables sliced from one folder via `sources:` became sibling `Sources/<X>/` folders, with a byte-identical behaviour set and a fully green test suite across the migration.

## The rule: grouping FILES within a unit

1. **Group related files in a shared parent folder.** When you have several files of the same semantic kind (e.g. 27 importers, 5 renderers, 12 view-models), put them under a single parent folder named for the kind (`Importers/`, `Renderers/`, `ViewModels/`). Do not scatter them across the root or across one-folder-per-file silos.

2. **Don't create a subfolder for a single file.** A subfolder's job is to make a group of related files easy to scan. A subfolder containing exactly one file forces an extra expand without giving anything back; that one file should live one level up.

3. **Exception: a single-file folder is allowed when the file's semantic differs sharply from its siblings.** Use this when the file *anchors a future group* or when collapsing it up would put it next to unrelated things. Example: the first file dropped into a brand-new utility / domain bucket may keep its own folder so the bucket's purpose is visible even before peers arrive. Apply sparingly. The default is to flatten.

4. **The rule applies recursively at every nesting level.** Each level of nesting must have a semantic justification. After grouping a kind into a parent folder (`Importers/`), look INSIDE it: are there sub-clusters that share a finer semantic? Pull those into their own subfolders. Then look UP one level: is the parent kind folder a peer of other related kind folders (an importer seam + importer utilities + importer concretes are all import-related)? Wrap them in a common ancestor (`Import/`). Walk the tree once top-down, once bottom-up. Every folder boundary at every depth must answer "what semantic distinguishes the things inside from the things outside?" If it cannot, flatten or rename.

## Naming the parent folder: singular vs plural

The kind folder's name is **singular**, not plural. A folder grouping many models is `Model/`, not `Models/`. A folder grouping many passes is `Pass/`, not `Passes/`. The folder name describes the *kind of thing inside*, not the *plural cardinality of that thing*. Singular reads cleaner in paths (`Sources/Enrichment/Model/EnrichmentRunner.swift` vs the noisier `Sources/Enrichment/Models/...`) and matches namespace style (`Indexer.Model.X`, not `Indexer.Models.X`).

Exception: the kind-folder name is plural *only when the kind itself is grammatically a plural noun* (`Resources/`, `Frameworks/`, `Sources/` itself). When you have to coin a singular vs plural, pick singular.

## Default: every unit is its own top-level folder

The package-manager default, `Sources/<Unit>/<files>` with no `path:` override, is the safer baseline for trees with many units. The filesystem location mirrors the unit identity one-to-one, which means:

- Listing the source root enumerates every unit without reading the manifest.
- Grepping one unit's folder answers "what's in unit Foo" without ambiguity.
- Lift-out is trivial: copy the folder, write a tiny standalone manifest, build.
- New contributors do not have to learn an additional layer of conventions before navigating the tree.

Deviate from the default ONLY when one of the two patterns below earns its keep.

## When family-parent folders are worth it: same-kind clusters of single-file units

A family parent folder with `path:` + `sources:` overrides earns its keep when you have **5 or more peer units of the same semantic kind**, each a single-file standalone unit. The canonical case: 27 importers under `Sources/Importers/<name>` files. The kind folder collapses 27 single-file siblings into one scannable list, while the manifest's `path:` + `sources:` keeps each importer a separate unit.

Rule of thumb: if you can name the kind in one word and you have many peers, group them. `Importers/`, `Renderers/`, `ViewModels/` qualify. Two units do not.

## When family-parent folders are *not* worth it: heterogeneous-kind families

A family folder with **kind-named subfolders** (`Sources/<Family>/{Core, Model, ...}/`, each subfolder holding a different kind of unit: live concrete vs foundation seam vs adapter) is an anti-pattern. It looks symmetric but:

- The filesystem path no longer maps 1:1 to a unit. `Sources/Enrichment/Core/` is the unit `Enrichment`; `Sources/Enrichment/Model/` is the unit `EnrichmentModels`. The reader needs the manifest to make the connection.
- Overloads the word "Core" across several meanings (family root, unit's content, kind subfolder).
- Reads worse: `Sources/Source/SampleCode/SampleCodeSource` triples the same word.
- Forces every new contributor to learn a project-specific taxonomy before navigating.

If a `Foo` unit ships alongside `FooModels`, leave them as `Sources/Foo/` + `Sources/FooModels/` (default). The naming pair already signals the relationship; folder nesting adds nothing.

**Historical note**: one project tried `Sources/<Family>/{Core, Model, ...}/` across 13 families before reverting to the default after a single review pass ("this is confusing"). The lesson: filesystem === unit boundary is load-bearing for navigability; family-parent folders that obscure it are not worth the cohesion gain.

## Unit name vs folder name decoupling

Unit identity is declared in the manifest (a `path:` override in SPM). The filesystem location and the unit name can diverge, but **do not make them diverge for cosmetic reasons**. Use a `path:` override only when:

1. **Clustering same-kind single-file units** (the importers case).
2. **Embedding a sub-unit inside a parent unit's folder** (e.g. `Sources/MCP/Core/`, `Sources/MCP/Client/`: each its own unit, sharing the umbrella name because they ship together as one conceptual framework).
3. **Test units pre-organised under a domain folder** when the source side mirrors that shape.

Anywhere else: keep the default. The discoverability win outweighs any cohesion gain.

## Rename priority order (highest-stability first)

When restructuring or renaming, treat the surfaces in this order. The higher the stability rank, the more reluctant you must be to change it. **Always anchor a rename around the highest-stability surface that is not moving**, and let the lower-rank surfaces follow.

1. **Buildable-unit name** (*highest stability*). This is the string consumers write to import the unit. Changing it cascades to every consumer's source file, every test, every doc that names the import, every script that greps for it. Default position: do not rename. A unit rename is a separate, dedicated change with explicit acceptance criteria (every consumer updated, every test green, every doc swept).

2. **Public type / namespace name** (*high stability*). Surfaces in consumer code as `<Unit>.<Type>`. Renames are tractable because they can be staged behind a back-compat alias, but every direct reference still needs updating eventually. Stage the rename: introduce the new name + alias in one change, migrate consumers in follow-ups, drop the alias when uses hit zero.

3. **File name** (*low stability*). Most compilers do not care which file a type lives in. Rename freely. Move the file and you are done; no consumer is affected.

4. **Folder layout** (*lowest stability*). The filesystem location of source files is an organisational decision, not an identity one. A `path:` override decouples folder from unit name when needed (sparingly, see above). Reorganise folders without touching unit names: every consumer keeps building unchanged.

**The load-bearing principle**: when renaming, ask first *"can I do this without touching the buildable-unit name?"* If yes, the change is local; only the author sees the file moves. If no, the change is API-breaking and needs the heavy treatment.

**Worked example**: a family-folder restructure tried to deepen a codebase by moving files into family-parent + kind-subfolder shapes. The instinct was right (organize better) but the execution prioritised the wrong surface (folder layout over unit name). After a single review pass ("this is confusing") the right move was to keep unit names + file names exactly as they were and revert the folder layout to default. The same change also landed type-name deepening (rank 2) behind back-compat aliases, which DID stick because it respected the priority order: unit names unchanged, public types staged behind aliases, file names + folders adjusted to match. The folder restructure (rank 4) cost roughly 250 file moves in then out; the type deepening (rank 2) cost about 6 files and shipped. Different ranks, different blast radii.

## How to apply

When adding a new file:

- Find an existing folder of the same kind. Drop the new file directly into it (no inner subfolder).
- If the file has its own companion files (a 2-or-more-file unit: protocol + helper + fixture, or model + parser), give *that unit* its own subfolder inside the parent kind folder.
- If no kind folder exists yet and the new file is the first of its kind, drop it next to its peers at the current level. Create the kind folder later, when a 2nd peer lands.

When reviewing an existing tree:

- Walk it folder-by-folder. Any folder containing exactly one source file is a candidate to flatten.
- Flatten by moving the file up one level and removing the now-empty folder.
- Preserve the unit-with-multiple-files rule: do not flatten a 2-file folder.

## How this composes with a package manager (Swift / SPM specifics)

This rule conflicts with SPM's default `Sources/<Target>/<files>` convention when you have many single-file targets, because SPM expects one folder per target. Resolve by giving each affected target an explicit `path:` and `sources:` declaration in the manifest. Multiple targets MAY share the same `path:` as long as each declares a disjoint `sources:` list:

```swift
let importersSrc = "Sources/Importers"

func flatImporter(_ name: String, dependencies: [Target.Dependency]) -> Target {
    .target(
        name: name,
        dependencies: dependencies,
        path: importersSrc,
        sources: ["\(name).swift"]
    )
}
```

Then `flatImporter("AnalysesImporter", ...)`, `flatImporter("FollowersImporter", ...)`, etc. all live as flat files under `Sources/Importers/` while remaining independent targets. A multi-file unit (e.g. one with a protocol + a parser) keeps its own subfolder under the parent kind folder: `path: "Sources/Importers/CsvImporter"`. Verified on Swift 6.0 + SPM: `path:` may overlap between targets when `sources:` partitions them disjointly.

## Tests follow sources

Test files mirror their source layout:

- 26 single-file importers under `Sources/Importers/` map to 26 test files under `Tests/Importers/`.
- A multi-file importer at `Sources/Importers/CsvImporter/` maps to a multi-file test unit at `Tests/Importers/CsvImporterTests/`.

Use the same flat-helper pattern in the manifest for tests.

## Why this matters

Two costs the rule removes:

- **Scan cost.** A tree with 27 one-file folders is 27 expand-arrows the reader has to click. A flat `Importers/` directory with 27 files visible at once is one find-in-files away from any unit. Brevity wins.
- **Mental overhead during edits.** When all importers are siblings, "show me what every importer does" is a single directory listing. When each importer hides one level down, the same question becomes a recursive find plus a mental merge.

The cost the rule preserves: unit independence (every unit lifts out of the set cleanly). Folder-grouping is a *filesystem* layout decision; unit boundaries stay sharp via `path:` + `sources:`.

## Lift-out preservation (non-negotiable)

Every unit must lift out as a working standalone package: copy the unit + its declared transitive deps to a tmp directory, generate a minimal manifest, build, green. Folder-grouping must not regress this. It does not, because:

- Each unit still owns a definite set of files (declared via `path:` + `sources:`). The filesystem locations are colocated, but the file-to-unit mapping is unambiguous.
- A lifted unit re-roots its sources under the default convention (`Sources/<Unit>/<files>`); the shared-path trick was a *set-level* layout choice, not part of the unit's identity. The lifted manifest goes back to a plain target declaration with no `path:` override.
- Tests follow the same rule: each test unit's files belong to exactly one test unit, and lifting copies just those files.

**Mechanical verification (do this when in doubt):** copy the unit + its declared transitive deps to a tmp `Sources/<Name>/<files>` (one folder per unit, default layout), generate a one-screen manifest, build. Green = lift-out works.

**Per-unit import audit must still work.** A side-effect of a shared `path:` is that simple `for d in Sources/*; do audit "$d"; done` scripts collapse a cluster of single-file units into one bucket and lose per-unit granularity. Fix: walk to leaf source files inside designated cluster directories. Add an `is_cluster_path` predicate to the audit so each clustered unit is still audited individually; update that predicate when adding a new cluster bucket. If the audit cannot distinguish your units, the refactor is leaking: fix the script or revert the grouping. The lift-out test never lies.

## Worked example: a three-pass flatten

Three passes, each from a different angle, illustrating rule item 4.

**Pass 1, flatten one-file folders.** Before: `Sources/AnalysesImporter/AnalysesImporter`, `Sources/FollowersImporter/FollowersImporter`, ... 27 one-file folders at the source root. After: `Sources/Importers/<name>` flat. The 2-file `CsvImporter` keeps its inner subfolder.

**Pass 2, sub-cluster inside the kind folder.** The flat list `Importers/` still had visible clusters: several files sharing a platform prefix. Each cluster got its own subfolder under `Importers/`. Single-file importers with no platform peer stayed flat at `Importers/`.

**Pass 3, wrap the import family at the root.** The source root contained `Importer/` (seam), `ImporterUtilities/` (helpers), and `Importers/` (concretes) as three peer folders mixed with unrelated things. The three import-related folders got wrapped under `Sources/Import/`:

```
Sources/Import/
|-- Importer/                    (seam, multi-file)
|-- ImporterUtilities/           (helpers, multi-file)
+-- Importers/                   (concretes)
    |-- PlatformA/               (multiple PlatformA units)
    |-- PlatformB/               (multiple PlatformB units)
    |-- AnalysesImporter         (flat, no platform peer)
    +-- SnapshotImporter
```

Tests mirror the same shape under `Tests/Import/`. Build + tests all pass.

The lesson: pass 1 and pass 2 are both applications of the same rule at different depths. Pass 3 inverts the angle, looking UP from a kind folder at its peers, and finds the next grouping. After three passes the tree settles: every folder at every depth has an answer to "what's inside that is not outside?"

## Anti-patterns

- Creating an `Importers/AnalysesImporter/AnalysesImporter` triple where the inner folder holds one file. Flatten.
- Hoisting a multi-file unit (e.g. an importer's protocol + parser) out of its subfolder and into the flat parent. The unit deserves its own folder.
- Inventing a single-file kind folder before peers exist (a brand-new `Renderers/WebDashboardRenderer` when no other renderer is anywhere on the horizon). Wait for a 2nd renderer, then create `Renderers/` and consolidate.
- Creating a parent kind folder that contains only one item *and* duplicates its name (e.g. `Renderers/Renderers/Web`). Same anti-pattern as `Renderers/Web/Web`: the inner layer is empty.

## Acceptance check

A tree conforms when: (1) listing the source root enumerates every buildable unit (no `path:` pointing many units into one shared parent except the two earned-exception patterns); (2) no folder holds exactly one source file unless rule item 3 (sharp-semantic anchor) applies; (3) every folder at every depth answers "what is inside that is not outside?"; (4) kind folders are singular unless the kind is grammatically plural; and (5) every unit still lifts out as a standalone package and builds green. Eyeball it before declaring a layout change done:

```bash
find Sources -mindepth 1 -maxdepth 1 -type d | while read -r d; do
  count=$(find "$d" -maxdepth 1 -type f | wc -l | tr -d ' ')
  printf "%3s  %s\n" "$count" "$d"
done | sort -n
```

Any line with `1` is a candidate for flattening (unless rule item 3 applies).

## Companion rules

- `no-shortcuts-first-principles.md`: the ethic this specializes. A folder boundary with no semantic behind it is accidental complexity inherited from the first layout that came to mind; deriving the tree from real boundaries is first-principles work.
- A file-naming convention is the layer this layout sits on top of; filenames inside a kind folder follow it.

## Why this exists

The filesystem boundary should mean something. When it mirrors a real semantic boundary (one folder per buildable unit, one kind folder per group of same-kind files), the tree is navigable by listing and grepping alone, and every unit lifts out cleanly. When folders proliferate without semantics (one-file folders, kind-subfolders that hide the unit identity), every navigation costs an extra click and every contributor has to learn a private taxonomy first. The rule keeps the boundary load-bearing.
