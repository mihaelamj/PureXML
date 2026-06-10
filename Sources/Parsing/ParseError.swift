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
        case undefinedEntity(name: String, Mark)
        case recursiveEntity(name: String, Mark)
        case amplificationLimitExceeded(Mark)
        case unexpectedEndTag(name: String, Mark)
        case undefinedNamespacePrefix(prefix: String, Mark)
        case junkAfterDocumentElement(Mark)
        case nestingTooDeep(limit: Int, Mark)
        case nameTooLong(limit: Int, Mark)
        case contentTooLong(limit: Int, Mark)
        /// A `<!DOCTYPE ...>` declaration was found. DTD processing is disabled by
        /// default as a security posture (XXE, entity-expansion DoS); enabling it
        /// is a deliberate future opt-in, not silent behavior.
        case unsupportedDoctype(Mark)
        /// Raised when raw bytes cannot be decoded in the detected encoding (for
        /// example an odd-length UTF-16 stream).
        case malformedEncoding
        /// Raised by entry points whose parsing path is not implemented yet.
        case notImplemented(String)
        /// The XML declaration `<?xml ... ?>` is malformed: its pseudo-attributes
        /// are out of order, unknown, or carry an illegal value.
        case malformedDeclaration(Mark)
        /// A comment contains `--`, which XML 1.0 forbids inside comments.
        case doubleHyphenInComment(Mark)
        /// An attribute value contains a raw `<`, which must be escaped.
        case rawLessThanInAttribute(Mark)
        /// Character data contains the literal `]]>` sequence, which must be
        /// escaped outside a CDATA section.
        case cdataCloseInContent(Mark)
        /// Two attributes are not separated by whitespace.
        case missingSpaceBeforeAttribute(Mark)
        /// A character outside the XML `Char` production appears in content.
        case invalidCharacter(Mark)
        /// A processing instruction uses the reserved target `xml` (any case),
        /// which is only legal as the document's XML declaration.
        case reservedProcessingInstructionTarget(Mark)

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
            case let .undefinedEntity(name, mark):
                "entity '&\(name);' is not declared at \(mark)"
            case let .recursiveEntity(name, mark):
                "entity '&\(name);' refers to itself at \(mark)"
            case let .amplificationLimitExceeded(mark):
                "entity expansion exceeds the amplification limit at \(mark)"
            case let .unexpectedEndTag(name, mark):
                "unexpected end tag </\(name)> at \(mark)"
            case let .undefinedNamespacePrefix(prefix, mark):
                "namespace prefix '\(prefix)' is not bound at \(mark)"
            case let .junkAfterDocumentElement(mark):
                "content after the root element at \(mark)"
            case let .nestingTooDeep(limit, mark):
                "element nesting exceeds the limit of \(limit) at \(mark)"
            case let .nameTooLong(limit, mark):
                "name exceeds the length limit of \(limit) at \(mark)"
            case let .contentTooLong(limit, mark):
                "content exceeds the length limit of \(limit) at \(mark)"
            case let .unsupportedDoctype(mark):
                "DTD processing is disabled (DOCTYPE at \(mark))"
            case .malformedEncoding:
                "input bytes are malformed for the detected encoding"
            case let .notImplemented(detail):
                "not implemented: \(detail)"
            case let .doubleHyphenInComment(mark):
                "'--' is not allowed inside a comment at \(mark)"
            case let .rawLessThanInAttribute(mark):
                "raw '<' is not allowed in an attribute value at \(mark)"
            case let .cdataCloseInContent(mark):
                "']]>' must be escaped in character data at \(mark)"
            case let .missingSpaceBeforeAttribute(mark):
                "attributes must be separated by whitespace at \(mark)"
            case let .invalidCharacter(mark):
                "character is not allowed in XML content at \(mark)"
            case let .reservedProcessingInstructionTarget(mark):
                "the processing-instruction target 'xml' is reserved at \(mark)"
            case let .malformedDeclaration(mark):
                "malformed XML declaration at \(mark)"
            }
        }
    }
}
