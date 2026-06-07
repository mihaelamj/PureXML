public extension PureXML.Parsing {
    /// Parser error with source position information when available.
    enum ParseError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case emptyDocument
        case unexpectedEndOfInput(Mark)
        case unexpectedCharacter(Character, Mark)
        case unterminatedTag(Mark)
        case unterminatedComment(Mark)
        case unterminatedCDATA(Mark)
        case mismatchedEndTag(expected: String, found: String, Mark)
        case duplicateAttribute(name: String, Mark)
        case expectedName(Mark)
        case expectedEquals(Mark)
        case unquotedAttributeValue(Mark)
        case invalidReference(String, Mark)
        case unexpectedEndTag(name: String, Mark)
        case junkAfterDocumentElement(Mark)
        /// A `<!DOCTYPE ...>` declaration was found. DTD processing is disabled by
        /// default as a security posture (XXE, entity-expansion DoS); enabling it
        /// is a deliberate future opt-in, not silent behavior.
        case unsupportedDoctype(Mark)
        /// Raised by entry points whose parsing path is not implemented yet.
        case notImplemented(String)

        public var description: String {
            switch self {
            case .emptyDocument:
                "document is empty"
            case let .unexpectedEndOfInput(mark):
                "unexpected end of input at \(mark)"
            case let .unexpectedCharacter(character, mark):
                "unexpected character '\(character)' at \(mark)"
            case let .unterminatedTag(mark):
                "unterminated tag starting at \(mark)"
            case let .unterminatedComment(mark):
                "unterminated comment starting at \(mark)"
            case let .unterminatedCDATA(mark):
                "unterminated CDATA section starting at \(mark)"
            case let .mismatchedEndTag(expected, found, mark):
                "expected </\(expected)> but found </\(found)> at \(mark)"
            case let .duplicateAttribute(name, mark):
                "duplicate attribute '\(name)' at \(mark)"
            case let .expectedName(mark):
                "expected a name at \(mark)"
            case let .expectedEquals(mark):
                "expected '=' after attribute name at \(mark)"
            case let .unquotedAttributeValue(mark):
                "attribute value must be quoted at \(mark)"
            case let .invalidReference(reference, mark):
                "invalid reference '\(reference)' at \(mark)"
            case let .unexpectedEndTag(name, mark):
                "unexpected end tag </\(name)> at \(mark)"
            case let .junkAfterDocumentElement(mark):
                "content after the root element at \(mark)"
            case let .unsupportedDoctype(mark):
                "DTD processing is disabled (DOCTYPE at \(mark))"
            case let .notImplemented(detail):
                "not implemented: \(detail)"
            }
        }
    }
}
