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
            "area", "base", "basefont", "br", "col", "embed", "frame", "hr",
            "img", "input", "isindex", "link", "meta", "param", "source",
            "track", "wbr",
        ]

        /// Raw-text elements: their content is taken verbatim up to the matching
        /// end tag, not parsed as markup.
        static let rawText: Set<String> = ["script", "style", "textarea", "title"]

        /// Boolean attributes, serialized minimized when their value repeats
        /// their name (the html output form).
        static let booleanAttributes: Set<String> = [
            "checked", "selected", "disabled", "readonly", "multiple", "ismap",
            "defer", "declare", "noresize", "nowrap", "noshade", "compact",
        ]

        /// HTML 4 attributes whose value is a URI (type %URI). The html output
        /// method percent-escapes non-ASCII and control characters in their
        /// values (XSLT 1.0 16.2, HTML 4.01 appendix B.2.1).
        static let uriAttributes: Set<String> = [
            "action", "archive", "background", "cite", "classid", "codebase",
            "data", "href", "longdesc", "profile", "src", "usemap",
        ]

        /// RCDATA elements: like raw-text, but character references in their
        /// content are decoded (`title`, `textarea`). The remaining raw-text
        /// elements (`script`, `style`) take their content with no decoding.
        static let rcdata: Set<String> = ["textarea", "title"]

        /// For an opening tag (key), the set of currently-open elements it
        /// implicitly closes first (the common optional-end-tag rules).
        static let impliedClose: [String: Set<String>] = [
            "li": ["li"],
            "dt": ["dt", "dd"],
            "dd": ["dt", "dd"],
            "p": ["p"],
            "option": ["option"],
            "optgroup": ["option", "optgroup"],
            "tr": ["tr", "td", "th"],
            "td": ["td", "th"],
            "th": ["td", "th"],
            "thead": ["tbody", "thead", "tfoot"],
            "tbody": ["tbody", "thead", "tfoot"],
            "tfoot": ["tbody", "thead", "tfoot"],
        ]
    }
}
