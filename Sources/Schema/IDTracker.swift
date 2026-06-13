extension PureXML.Schema {
    /// Accumulates `xs:ID` and `xs:IDREF`/`xs:IDREFS` values across an instance
    /// document and reports the document-scoped violations XSD requires: every ID
    /// is unique across the document, and every IDREF/IDREFS item matches some ID.
    /// These are not simple-type (lexical) checks; they need the whole document,
    /// so the tree validator records here during its typed walk and reports after.
    final class IDTracker {
        private var seenIDs: Set<String> = []
        private var duplicates: [PureXML.Validation.ValidationError] = []
        private var references: [(value: String, path: [PureXML.Validation.PathKey])] = []

        func recordID(_ value: String, at path: [PureXML.Validation.PathKey]) {
            if !seenIDs.insert(value).inserted {
                duplicates.append(.init(reason: "duplicate ID '\(value)'", at: path))
            }
        }

        func recordReference(_ value: String, at path: [PureXML.Validation.PathKey]) {
            references.append((value, path))
        }

        /// Duplicate-ID errors plus an error for every reference with no matching
        /// ID. Resolution runs after the whole document is seen, so a reference may
        /// point at an ID declared later.
        func errors() -> [PureXML.Validation.ValidationError] {
            var result = duplicates
            for reference in references where !seenIDs.contains(reference.value) {
                result.append(.init(reason: "IDREF '\(reference.value)' has no matching ID", at: reference.path))
            }
            return result
        }
    }
}

extension PureXML.Schema.SimpleType {
    /// Whether this is `xs:ID` (or an atomic restriction of it).
    var isID: Bool {
        if case .atomic = variety { return base == .id }
        return false
    }

    /// Whether this is `xs:IDREF` (or an atomic restriction of it).
    var isIDReference: Bool {
        if case .atomic = variety { return base == .idref }
        return false
    }

    /// Whether this is `xs:IDREFS` (a list whose item type is `xs:IDREF`).
    var isIDReferenceList: Bool {
        if case let .list(item) = variety { return item.base == .idref }
        return false
    }
}
