# File Naming Rules

**Status: house convention for committed filenames.** Every file committed to the repository follows these conventions: lowercase, dash-separated, ASCII, ISO dates. This is the filename companion to `commits.md` (the same discipline applied to commit text): a name a future reader can predict, type, and glob without surprises.

## General rules

- **Lowercase only**: no uppercase letters in filenames.
- **Dashes for separators**: use `-` instead of spaces, underscores, or camelCase.
- **No spaces**: ever.
- **No special characters**: no accented letters, `()`, `[]`, `&`. Transliterate accented characters to plain ASCII (for example, c-with-caron to `c`, s-with-caron to `s`, d-with-stroke to `dj`).
- **No trailing dots**: remove any dot before the file extension.
- **ASCII only**: filenames must be plain ASCII.

## Date format in filenames

Always use the ISO format `YYYY-MM-DD`:

- `30.11.2023` -> `2023-11-30`
- `11.03.2024.` -> `2024-03-11`
- `Mar 24, 2025` -> `2025-03-24`

## Document naming patterns

### Scanned documents

```
Scan MMM DD, YYYY at HH.MM.pdf    -> scan-YYYY-MM-DD-HH-MM.pdf
Scan DD.MM.YYYY. at HH.MM.pdf     -> scan-YYYY-MM-DD-HH-MM.pdf
Scan DD MMM YYYY at HH.MM.pdf     -> scan-YYYY-MM-DD-HH-MM.pdf
```

### Photos

```
IMG_XXXX.jpeg                      -> keep as-is (acceptable)
IMG_XXXX.HEIC                      -> convert to IMG_XXXX.jpg
Photo DD-MM-YYYY.heic              -> photo-YYYY-MM-DD.jpg (convert + rename)
```

### Dated documents

```
<type>-<description>-YYYY-MM-DD.<ext>
```

Use a date suffix only when the document is date-specific; omit it otherwise. Neutral examples:

```
invoice-2024-03-01.pdf
design-notes-2025-06-14.md
release-checklist.md          # not date-specific, no suffix
```

## Renaming existing files

When renaming, use `git mv` to preserve history:

```bash
git mv "Old File Name.pdf" "old-file-name.pdf"
```

Commit: `rename: normalize filenames`

## Audit (before any processing)

Run these in the repo before reporting counts:

```bash
# Files with spaces
find <repo> -name "* *" -not -path "*/.git/*" -not -name "*.md"

# Files with uppercase
find <repo> -regex ".*/[^/]*[A-Z][^/]*" -not -path "*/.git/*" -not -name "README*" -not -name "*.md"

# Files with underscores (excluding .git)
find <repo> -name "*_*" -not -path "*/.git/*" -not -name "*.md"

# HEIC files
find <repo> \( -name "*.heic" -o -name "*.HEIC" \) -not -path "*/.git/*"
```

A clean repo returns nothing from the first three queries (the README and `.md` exclusions cover the conventional exceptions).

## Skip list

Some asset paths legitimately carry vendor-supplied names and are exempt from the audit. Document the skip paths per repo (for example, browser-extension resource folders, generated asset bundles, vendor media dumps). Keep the list short and justified: every exemption is a name a reader cannot predict, so it must earn its place.

## Companion rules

- `commits.md`: the same lowercase/dashed/ASCII/ISO discipline applied to commit messages and branch names.
- `no-shortcuts-first-principles.md`: an unpredictable filename committed "just this once" is a small shortcut that compounds across a tree.

## Why this exists

Filenames are an interface. A predictable scheme means a reader can guess a path, a glob can match a set, and a sort orders by date without a parser. Mixed case, spaces, and locale-specific characters break globs, confuse case-insensitive filesystems, and force quoting. The convention costs nothing at creation time and saves every later reader.
