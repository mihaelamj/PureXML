/// Scans an XPointer into its scheme parts, each already translated to an XPath
/// expression. File-scope and private: an internal detail of
/// ``PureXML/XPointer/Pointer``.
private struct PointerScanner {
    typealias XPointerError = PureXML.XPointer.XPointerError

    private let chars: [Character]
    private var index = 0

    private init(_ pointer: String) {
        chars = Array(pointer)
    }

    static func parts(of pointer: String) throws -> [String] {
        let trimmed = pointer.trimmingXMLWhitespace()
        guard !trimmed.isEmpty else { throw XPointerError.empty }
        // A bare name with no scheme parentheses is a shorthand pointer: id(name).
        if !trimmed.contains("(") {
            return ["id('\(trimmed)')"]
        }
        var scanner = PointerScanner(trimmed)
        return try scanner.scanSchemes()
    }

    private mutating func scanSchemes() throws -> [String] {
        var parts: [String] = []
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

    private func translate(scheme: String, data: String) throws -> String {
        switch scheme {
        case "xpointer": data
        case "element": Self.elementToXPath(data)
        default: throw XPointerError.unknownScheme(scheme)
        }
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
    /// A compiled XPointer over the `element()` and `xpointer()` schemes, plus the
    /// shorthand bare-name form (`name`, equivalent to `id('name')`). A pointer
    /// may chain several scheme parts; they are tried in order and the first that
    /// selects a non-empty node-set wins (the XPointer fallback rule).
    ///
    /// `element(id/2/3)` navigates by child-element position from an id (or the
    /// document root for a leading `/`); `xpointer(expr)` evaluates a full XPath
    /// expression. Reimplemented over ``PureXML/XPath``.
    struct Pointer: Sendable {
        private let parts: [String]

        /// Compiles an XPointer string.
        public init(_ pointer: String) throws {
            parts = try PointerScanner.parts(of: pointer)
        }

        /// Evaluates the pointer over a node, returning the first scheme part's
        /// non-empty selection in document order, or an empty list.
        public func evaluate(over node: PureXML.Model.Node) -> [PureXML.XPath.Selection] {
            for part in parts {
                guard let query = try? PureXML.XPath.Query(part) else { continue }
                let result = query.evaluate(over: node)
                if !result.isEmpty { return result }
            }
            return []
        }
    }

    /// Compiles and evaluates an XPointer over a node in one step.
    static func evaluate(_ pointer: String, over node: PureXML.Model.Node) throws -> [PureXML.XPath.Selection] {
        try Pointer(pointer).evaluate(over: node)
    }
}
