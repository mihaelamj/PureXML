public extension PureXML {
    /// A single text edit an editor can apply: replace `range` with `replacement`.
    /// An insertion is a zero-width range at the insertion point.
    struct TextEdit: Equatable, Sendable {
        public var range: Parsing.SourceRange
        public var replacement: String

        public init(range: Parsing.SourceRange, replacement: String) {
            self.range = range
            self.replacement = replacement
        }
    }

    /// An offered fix: a human-readable title and the edits that apply it.
    struct QuickFix: Equatable, Sendable {
        public var title: String
        public var edits: [TextEdit]

        public init(title: String, edits: [TextEdit]) {
            self.title = title
            self.edits = edits
        }
    }

    /// Derives quick-fixes from the *structured* schema completions of an element
    /// (never from parsing a diagnostic message): a required-but-absent attribute
    /// becomes an insertion just before the start tag's `>`, and a still-expected
    /// required child becomes an insertion just before the end tag.
    enum QuickFixEngine {
        static func fixes(from completions: Schema.Completions, element: Model.TreeNode) -> [QuickFix] {
            guard let content = element.contentRange else { return [] }
            var fixes: [QuickFix] = []

            // The `>` of the start tag sits one character before the content start.
            let tagEnd = Parsing.Mark(
                line: content.start.line,
                column: Swift.max(1, content.start.column - 1),
                offset: Swift.max(0, content.start.offset - 1),
            )
            let attributePoint = Parsing.SourceRange(start: tagEnd, end: tagEnd)
            for attribute in completions.attributes where attribute.required && !attribute.present {
                fixes.append(QuickFix(
                    title: "Add required attribute '\(attribute.name)'",
                    edits: [TextEdit(range: attributePoint, replacement: " \(attribute.name)=\"\"")],
                ))
            }

            if !completions.complete, let next = completions.elements.first {
                let childPoint = Parsing.SourceRange(start: content.end, end: content.end)
                fixes.append(QuickFix(
                    title: "Insert <\(next)>",
                    edits: [TextEdit(range: childPoint, replacement: "<\(next)></\(next)>")],
                ))
            }
            return fixes
        }
    }
}
