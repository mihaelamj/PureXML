extension PureXML.Parsing {
    /// Tracks in-scope namespace bindings as elements open and close, resolving
    /// qualified names to their namespace URI. The reserved `xml` and `xmlns`
    /// prefixes are built in. Internal to the parser.
    ///
    /// Follows the XML Namespaces rules: a default namespace (`xmlns="..."`)
    /// applies to unprefixed element names but never to attribute names, an empty
    /// declaration undeclares a binding, and an unbound prefix is an error.
    struct NamespaceContext {
        /// The reserved binding for the `xml` prefix.
        static let xmlNamespaceURI = "http://www.w3.org/XML/1998/namespace"
        /// The namespace name reserved for `xmlns` itself; it may never be
        /// bound by a declaration.
        static let xmlnsNamespaceURI = "http://www.w3.org/2000/xmlns/"

        /// The current in-scope bindings, prefix ("" = default namespace) to URI,
        /// maintained incrementally so a lookup is O(1) rather than a walk over a
        /// stack as deep as the document: a per-element walk would make parsing a
        /// deeply-nested document quadratic in depth.
        private var current: [String: String] = [:]

        /// One restore list per open element: the bindings it overwrote, so
        /// closing the element can return `current` to its enclosing state. Each
        /// entry is a prefix and the value it had before this element (nil when it
        /// was unbound), applied in reverse on exit.
        private var undo: [[(key: String, previous: String?)]] = []

        /// Opens an element: applies its `xmlns` declarations to the current
        /// bindings, then resolves the element name and its attribute names
        /// against the now-in-scope bindings.
        mutating func enterElement(
            name: PureXML.Model.QualifiedName,
            attributes: [PureXML.Model.Attribute],
            at mark: Mark,
        ) throws -> (name: PureXML.Model.QualifiedName, attributes: [PureXML.Model.Attribute]) {
            try checkNameShape(name, at: mark)
            var changes: [(key: String, previous: String?)] = []
            for attribute in attributes {
                try checkNameShape(attribute.name, at: mark)
                if attribute.name.prefix == nil, attribute.name.localName == "xmlns" {
                    try checkDefaultBinding(attribute.value, at: mark)
                    changes.append((key: "", previous: current[""]))
                    current[""] = attribute.value
                } else if attribute.name.prefix == "xmlns" {
                    try checkPrefixBinding(attribute.name.localName, uri: attribute.value, at: mark)
                    let key = attribute.name.localName
                    changes.append((key: key, previous: current[key]))
                    current[key] = attribute.value
                }
            }
            undo.append(changes)

            let resolvedName = try resolveElement(name, at: mark)
            let resolvedAttributes = try attributes.map { try resolveAttribute($0, at: mark) }
            try checkExpandedNames(resolvedAttributes, at: mark)
            return (resolvedName, resolvedAttributes)
        }

        /// Closes an element, restoring the bindings it overwrote.
        mutating func leaveElement() {
            guard let changes = undo.popLast() else { return }
            // Restore in reverse so repeated bindings of one prefix on a single
            // element unwind to the value that preceded the element.
            for change in changes.reversed() {
                current[change.key] = change.previous
            }
        }

        private func resolveElement(
            _ name: PureXML.Model.QualifiedName,
            at mark: Mark,
        ) throws -> PureXML.Model.QualifiedName {
            if name.prefix == nil {
                return name.resolved(namespaceURI: lookup(""))
            }
            return try name.resolved(namespaceURI: requireURI(forPrefix: name.prefix, at: mark))
        }

        private func resolveAttribute(
            _ attribute: PureXML.Model.Attribute,
            at mark: Mark,
        ) throws -> PureXML.Model.Attribute {
            let name = attribute.name
            if name.prefix == nil || name.prefix == "xmlns" {
                return attribute
            }
            let uri = try requireURI(forPrefix: name.prefix, at: mark)
            return PureXML.Model.Attribute(name: name.resolved(namespaceURI: uri), value: attribute.value)
        }

        private func requireURI(forPrefix prefix: String?, at mark: Mark) throws -> String {
            if prefix == "xml" {
                return Self.xmlNamespaceURI
            }
            if let uri = lookup(prefix ?? ""), !uri.isEmpty {
                return uri
            }
            throw ParseError.undefinedNamespacePrefix(prefix: prefix ?? "", mark)
        }

        /// A qualified name has exactly one colon separating two non-empty
        /// NCNames; `QualifiedName` keeps a malformed raw form (`foo:`,
        /// `:foo`, `a:b:c`, `xmlns:`) in its local name, where the colon
        /// betrays it.
        private func checkNameShape(_ name: PureXML.Model.QualifiedName, at mark: Mark) throws {
            guard name.localName.contains(":") else { return }
            throw ParseError.namespaceConstraint(reason: "'\(name.description)' is not a legal qualified name", mark)
        }

        /// The reserved-binding rules for `xmlns:prefix` declarations: `xmlns`
        /// itself may never be declared, `xml` only with its own namespace
        /// name, no other prefix may take either reserved namespace name, and
        /// a prefix may not be undeclared in Namespaces 1.0.
        private func checkPrefixBinding(_ prefix: String, uri: String, at mark: Mark) throws {
            if prefix == "xmlns" {
                throw ParseError.namespaceConstraint(reason: "the 'xmlns' prefix must not be declared", mark)
            }
            if prefix == "xml" {
                guard uri == Self.xmlNamespaceURI else {
                    throw ParseError.namespaceConstraint(reason: "the 'xml' prefix is bound to '\(Self.xmlNamespaceURI)' and cannot be rebound", mark)
                }
                return
            }
            if uri == Self.xmlNamespaceURI || uri == Self.xmlnsNamespaceURI {
                throw ParseError.namespaceConstraint(reason: "the reserved namespace name '\(uri)' must not be bound to prefix '\(prefix)'", mark)
            }
            if uri.isEmpty {
                throw ParseError.namespaceConstraint(reason: "prefix '\(prefix)' may not be undeclared in Namespaces 1.0", mark)
            }
        }

        /// Neither reserved namespace name may become the default namespace.
        private func checkDefaultBinding(_ uri: String, at mark: Mark) throws {
            guard uri == Self.xmlNamespaceURI || uri == Self.xmlnsNamespaceURI else { return }
            throw ParseError.namespaceConstraint(reason: "the reserved namespace name '\(uri)' must not be the default namespace", mark)
        }

        /// Attributes must be distinct by expanded name: two prefixes bound to
        /// the same URI cannot carry the same local name on one element.
        private func checkExpandedNames(_ attributes: [PureXML.Model.Attribute], at mark: Mark) throws {
            var seen: Set<String> = []
            for attribute in attributes where attribute.name.namespaceURI != nil {
                let key = (attribute.name.namespaceURI ?? "") + "\u{0}" + attribute.name.localName
                guard seen.insert(key).inserted else {
                    throw ParseError.duplicateAttribute(name: attribute.name.description, mark)
                }
            }
        }

        private func lookup(_ key: String) -> String? {
            guard let uri = current[key], !uri.isEmpty else { return nil }
            return uri
        }
    }
}
