/// One part of an XPointer: either a selection expression (already translated to
/// XPath) or a namespace binding from an `xmlns()` scheme that applies to the
/// expression parts that follow it. File-scope and private.
private enum PointerPart {
    case expression(String)
    case namespace(prefix: String, uri: String)
    case range(PureXML.XPointer.RangeForm)
}

/// Scans an XPointer into its scheme parts, each already translated to an XPath
/// expression or a namespace binding. File-scope and private: an internal detail
/// of ``PureXML/XPointer/Pointer``.
private struct PointerScanner {
    typealias XPointerError = PureXML.XPointer.XPointerError

    private let chars: [Character]
    private var index = 0

    private init(_ pointer: String) {
        chars = Array(pointer)
    }

    static func parts(of pointer: String) throws -> [PointerPart] {
        let trimmed = pointer.trimmingXMLWhitespace()
        guard !trimmed.isEmpty else { throw XPointerError.empty }
        // A bare name with no scheme parentheses is a shorthand pointer: id(name).
        if !trimmed.contains("(") {
            return [.expression("id('\(trimmed)')")]
        }
        var scanner = PointerScanner(trimmed)
        return try scanner.scanSchemes()
    }

    private mutating func scanSchemes() throws -> [PointerPart] {
        var parts: [PointerPart] = []
        while true {
            skipSpace()
            guard !isAtEnd else { return parts }
            let scheme = scanName()
            guard !scheme.isEmpty, consume("(") else { throw XPointerError.malformed }
            let data = try scanData()
            try parts.append(translate(scheme: scheme, data: data))
        }
    }

    /// Reads the balanced parenthesized data after `(`, honoring quotes, and
    /// consumes the closing `)`.
    private mutating func scanData() throws -> String {
        var depth = 1
        var data = ""
        var quote: Character?
        while let character = peek() {
            advance()
            if let active = quote {
                if character == active { quote = nil }
                data.append(character)
                continue
            }
            switch character {
            case "'", "\"":
                quote = character
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return data }
            default:
                break
            }
            data.append(character)
        }
        throw XPointerError.malformed
    }

    private func translate(scheme: String, data: String) throws -> PointerPart {
        switch scheme {
        case "xpointer", "xpath1":
            if let form = PureXML.XPointer.RangeForm.parse(data) { return .range(form) }
            return .expression(data)
        case "element": return .expression(Self.elementToXPath(data))
        case "xmlns": return try Self.namespaceBinding(data)
        default: throw XPointerError.unknownScheme(scheme)
        }
    }

    /// Parses an `xmlns(prefix=uri)` datum into a namespace binding.
    private static func namespaceBinding(_ data: String) throws -> PointerPart {
        guard let equals = data.firstIndex(of: "=") else { throw XPointerError.malformed }
        let prefix = String(data[..<equals]).trimmingXMLWhitespace()
        let uri = String(data[data.index(after: equals)...]).trimmingXMLWhitespace()
        guard !prefix.isEmpty else { throw XPointerError.malformed }
        return .namespace(prefix: prefix, uri: uri)
    }

    /// Translates an `element()` scheme datum (`id/1/2`, `/1/2`, `id`) into the
    /// equivalent XPath: an id() start or the document root, then child-element
    /// positions.
    private static func elementToXPath(_ data: String) -> String {
        let segments = data.split(separator: "/", omittingEmptySubsequences: false)
        var result = ""
        for (offset, segment) in segments.enumerated() {
            if offset == 0 {
                result = segment.isEmpty ? "" : "id('\(segment)')"
            } else {
                result += "/*[\(segment)]"
            }
        }
        return result.isEmpty ? "/" : result
    }

    private var isAtEnd: Bool {
        index >= chars.count
    }

    private func peek() -> Character? {
        index < chars.count ? chars[index] : nil
    }

    private mutating func scanName() -> String {
        var name = ""
        while let character = peek(), character.isXMLNameContinuation {
            name.append(character)
            advance()
        }
        return name
    }

    @discardableResult
    private mutating func consume(_ character: Character) -> Bool {
        guard peek() == character else { return false }
        advance()
        return true
    }

    private mutating func advance() {
        if index < chars.count { index += 1 }
    }

    private mutating func skipSpace() {
        while let character = peek(), character == " " || character == "\t" || character == "\n" || character == "\r" {
            advance()
        }
    }
}

public extension PureXML.XPointer {
    /// A compiled XPointer over the `element()`, `xpointer()`, `xpath1()`, and
    /// `xmlns()` schemes, plus the shorthand bare-name form (`name`, equivalent to
    /// `id('name')`). A pointer may chain several scheme parts; selection parts are
    /// tried in order and the first that selects a non-empty node-set wins (the
    /// XPointer fallback rule).
    ///
    /// `element(id/2/3)` navigates by child-element position from an id (or the
    /// document root for a leading `/`); `xpointer(expr)` and `xpath1(expr)`
    /// evaluate a full XPath expression; `xmlns(p=uri)` binds the prefix `p` for the
    /// expression parts that follow it. Reimplemented over ``PureXML/XPath``.
    struct Pointer: Sendable {
        private let parts: [PointerPart]

        /// Compiles an XPointer string.
        public init(_ pointer: String) throws {
            parts = try PointerScanner.parts(of: pointer)
        }

        /// Evaluates the pointer over a node, returning the first selection scheme
        /// part's non-empty result in document order, or an empty list. An
        /// `xmlns()` part binds a prefix for the expression parts that follow it.
        public func evaluate(over node: PureXML.Model.Node) -> [PureXML.XPath.Selection] {
            var namespaces: [String: String] = [:]
            for part in parts {
                switch part {
                case let .namespace(prefix, uri):
                    namespaces[prefix] = uri
                case let .expression(xpath):
                    guard let query = try? PureXML.XPath.Query(xpath) else { continue }
                    let result = query.evaluate(over: node, namespaces: namespaces)
                    if !result.isEmpty { return result }
                case .range:
                    continue
                }
            }
            return []
        }

        /// Evaluates the pointer's range parts (`range()`, `range-to()`,
        /// `string-range()`), returning the first part's non-empty ranges in
        /// document order, or an empty list. An `xmlns()` part binds a prefix for
        /// the range parts that follow it. Use this for the XPointer range model
        /// (and XInclude range inclusion); ``evaluate(over:)`` covers the
        /// node-selecting schemes.
        public func evaluateRanges(over node: PureXML.Model.Node) -> [PureXML.XPointer.Range] {
            let root = PureXML.Model.TreeNode(node)
            var namespaces: [String: String] = [:]
            for part in parts {
                switch part {
                case let .namespace(prefix, uri):
                    namespaces[prefix] = uri
                case let .range(form):
                    let ranges = form.ranges(over: root, namespaces: namespaces)
                    if !ranges.isEmpty { return ranges }
                case .expression:
                    continue
                }
            }
            return []
        }
    }

    /// Compiles and evaluates an XPointer over a node in one step.
    static func evaluate(_ pointer: String, over node: PureXML.Model.Node) throws -> [PureXML.XPath.Selection] {
        try Pointer(pointer).evaluate(over: node)
    }

    /// Compiles and evaluates an XPointer's range parts over a node in one step.
    static func evaluateRanges(_ pointer: String, over node: PureXML.Model.Node) throws -> [Range] {
        try Pointer(pointer).evaluateRanges(over: node)
    }
}
