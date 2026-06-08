public extension PureXML.Emitting {
    /// Explicit emitter options. The default is pretty-printed output with
    /// two-space indentation and a self-closing tag for empty elements, and no
    /// XML declaration.
    /// Which quote character delimits attribute values in the output.
    enum QuoteStyle: Equatable, Hashable, Sendable {
        case double
        case single

        var character: Character {
            self == .double ? "\"" : "'"
        }
    }

    struct Options: Equatable, Hashable, Sendable {
        /// Whether to indent nested elements onto their own lines.
        public var prettyPrint: Bool
        /// The indentation unit used when ``prettyPrint`` is enabled.
        public var indent: String
        /// The quote character that delimits attribute values.
        public var attributeQuote: QuoteStyle
        /// The line terminator inserted by pretty-printing and after the
        /// declaration. A line feed by default; set to `\r\n` for CRLF output.
        public var lineEnding: String
        /// Whether childless elements collapse to `<name/>`.
        public var selfCloseEmptyElements: Bool
        /// Whether to emit a CDATA section's content as escaped text rather than as
        /// a `<![CDATA[ ... ]]>` section.
        public var cdataAsText: Bool
        /// Whether to escape every non-ASCII character as a numeric character
        /// reference, so the output is pure ASCII (libxml2's character-reference
        /// encoding).
        public var asciiOnly: Bool
        /// Whether to emit an `<?xml ...?>` declaration (libxml2 emits one by
        /// default when saving a document; PureXML defaults to off for fragments).
        public var includeXMLDeclaration: Bool
        /// The version written in the declaration.
        public var xmlVersion: String
        /// The encoding name written in the declaration, or nil to omit it.
        public var encodingName: String?
        /// The `standalone` flag written in the declaration, or nil to omit it.
        public var standalone: Bool?

        public init(
            prettyPrint: Bool = true,
            indent: String = "  ",
            attributeQuote: QuoteStyle = .double,
            lineEnding: String = "\n",
            selfCloseEmptyElements: Bool = true,
            cdataAsText: Bool = false,
            asciiOnly: Bool = false,
            includeXMLDeclaration: Bool = false,
            xmlVersion: String = "1.0",
            encodingName: String? = "UTF-8",
            standalone: Bool? = nil,
        ) {
            self.prettyPrint = prettyPrint
            self.indent = indent
            self.attributeQuote = attributeQuote
            self.lineEnding = lineEnding
            self.selfCloseEmptyElements = selfCloseEmptyElements
            self.cdataAsText = cdataAsText
            self.asciiOnly = asciiOnly
            self.includeXMLDeclaration = includeXMLDeclaration
            self.xmlVersion = xmlVersion
            self.encodingName = encodingName
            self.standalone = standalone
        }

        /// Pretty-printed output with two-space indentation.
        public static let `default` = Options()

        /// Single-line output with no inserted whitespace.
        public static let compact = Options(prettyPrint: false)

        /// The `<?xml ...?>` declaration string, or nil when not requested.
        var xmlDeclaration: String? {
            guard includeXMLDeclaration else { return nil }
            var declaration = "<?xml version=\"\(xmlVersion)\""
            if let encodingName {
                declaration += " encoding=\"\(encodingName)\""
            }
            if let standalone {
                declaration += " standalone=\"\(standalone ? "yes" : "no")\""
            }
            return declaration + "?>"
        }
    }
}
