# Verification Before Completion

Never claim a PureXML change is complete without fresh command output from the
relevant gates.

## Required Gate

Run this local gate before committing or reporting completion:

```sh
bash scripts/check-style.sh
bash scripts/check-namespacing.sh
bash scripts/check-forbidden-patterns.sh
bash scripts/check-changelog-touched.sh
swiftformat . --config .swiftformat --lint
swiftlint --config .swiftlint.yml --strict
swift build
swift test
bash scripts/check-linux.sh
bash scripts/check-wasm.sh
```

Hosted CI must also pass the Windows job, which runs `scripts/check-windows.ps1`.

## Claims and Evidence

| Claim | Required evidence |
|---|---|
| Style clean | `scripts/check-style.sh` exits 0 |
| Namespace clean | `scripts/check-namespacing.sh` exits 0 |
| Forbidden-pattern clean | `scripts/check-forbidden-patterns.sh` exits 0 |
| Format clean | `swiftformat . --config .swiftformat --lint` exits 0 |
| Lint clean | `swiftlint --config .swiftlint.yml --strict` exits 0 |
| Builds on macOS | `swift build` exits 0 |
| Tests pass | `swift test` exits 0 and reports zero failures |
| Linux compatible | `bash scripts/check-linux.sh` exits 0 |
| Windows compatible | hosted `scripts/check-windows.ps1` exits 0 |
| WASI compatible | `bash scripts/check-wasm.sh` exits 0 |

If a tool is unavailable, say so explicitly and do not claim that gate passed.
