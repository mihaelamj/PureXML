public extension PureXML.Parsing {
    /// A located problem found while reading a document. Unlike a thrown
    /// ``ParseError``, a diagnostic does not abort the read: the recovering reader
    /// records it, repairs as best it can, and continues, so an invalid document
    /// still yields a best-effort tree alongside the list of what went wrong.
    struct Diagnostic: Equatable, Sendable, CustomStringConvertible {
        /// A human-readable, already-located description of the problem.
        public var message: String
        /// The source position, when known.
        public var mark: Mark?

        public init(message: String, mark: Mark? = nil) {
            self.message = message
            self.mark = mark
        }

        public var description: String {
            message
        }
    }
}

extension PureXML.Parsing.Diagnostic {
    /// Wraps a thrown ``PureXML/Parsing/ParseError`` as a diagnostic, keeping its
    /// located message and structured position.
    init(_ error: PureXML.Parsing.ParseError) {
        self.init(message: error.description, mark: error.mark)
    }
}

public extension PureXML.Parsing.ParseError {
    /// The source position the error occurred at, when the case carries one.
    var mark: PureXML.Parsing.Mark? {
        switch self {
        case .emptyDocument, .malformedEncoding, .notImplemented:
            nil
        case let .unexpectedEndOfInput(mark), let .unterminatedTag(mark), let .unterminatedComment(mark),
             let .unterminatedCDATA(mark), let .expectedName(mark), let .expectedEquals(mark),
             let .unquotedAttributeValue(mark), let .amplificationLimitExceeded(mark),
             let .junkAfterDocumentElement(mark), let .unsupportedDoctype(mark), let .malformedDeclaration(mark):
            mark
        case let .unexpectedCharacter(_, mark), let .mismatchedEndTag(_, _, mark),
             let .duplicateAttribute(_, mark), let .invalidReference(_, mark),
             let .undefinedEntity(_, mark), let .recursiveEntity(_, mark),
             let .unexpectedEndTag(_, mark), let .undefinedNamespacePrefix(_, mark),
             let .nestingTooDeep(_, mark), let .nameTooLong(_, mark), let .contentTooLong(_, mark):
            mark
        }
    }
}
