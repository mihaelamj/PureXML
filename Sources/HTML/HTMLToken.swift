extension PureXML.HTML {
    /// A lexical token from the lenient HTML tokenizer.
    enum Token: Equatable, Sendable {
        case startTag(name: String, attributes: [(String, String)], selfClosing: Bool)
        case endTag(name: String)
        case text(String)
        case comment(String)
        case doctype(String)

        static func == (lhs: Token, rhs: Token) -> Bool {
            switch (lhs, rhs) {
            case let (.startTag(leftName, leftAttributes, leftClosing), .startTag(rightName, rightAttributes, rightClosing)):
                leftName == rightName && leftClosing == rightClosing
                    && leftAttributes.map(\.0) == rightAttributes.map(\.0)
                    && leftAttributes.map(\.1) == rightAttributes.map(\.1)
            case let (.endTag(left), .endTag(right)): left == right
            case let (.text(left), .text(right)): left == right
            case let (.comment(left), .comment(right)): left == right
            case let (.doctype(left), .doctype(right)): left == right
            default: false
            }
        }
    }

    /// The HTML element categories that drive lenient tree building and
    /// serialization.
    enum Elements {
        /// Void elements: no content and no end tag.
        static let void: Set<String> = [
            "area", "base", "br", "col", "embed", "hr", "img", "input",
            "link", "meta", "param", "source", "track", "wbr",
        ]

        /// Raw-text elements: their content is taken verbatim up to the matching
        /// end tag, not parsed as markup.
        static let rawText: Set<String> = ["script", "style", "textarea", "title"]

        /// For an opening tag (key), the set of currently-open elements it
        /// implicitly closes first (the common optional-end-tag rules).
        static let impliedClose: [String: Set<String>] = [
            "li": ["li"],
            "dt": ["dt", "dd"],
            "dd": ["dt", "dd"],
            "p": ["p"],
            "option": ["option"],
            "tr": ["tr", "td", "th"],
            "td": ["td", "th"],
            "th": ["td", "th"],
            "thead": ["tbody", "thead", "tfoot"],
            "tbody": ["tbody", "thead", "tfoot"],
            "tfoot": ["tbody", "thead", "tfoot"],
        ]
    }
}
