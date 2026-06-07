Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

swift --version
swift build
swift test
swift build -c release
swift test -c release
