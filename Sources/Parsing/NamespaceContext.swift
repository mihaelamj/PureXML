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

        /// A stack of scopes; each maps a prefix ("" = default namespace) to a URI.
        private var scopes: [[String: String]] = []

        /// Opens an element: pushes a scope built from its `xmlns` declarations,
        /// then resolves the element name and its attribute names against the
        /// now-in-scope bindings.
        mutating func enterElement(
            name: PureXML.Model.QualifiedName,
            attributes: [PureXML.Model.Attribute],
            at mark: Mark,
        ) throws -> (name: PureXML.Model.QualifiedName, attributes: [PureXML.Model.Attribute]) {
            var scope: [String: String] = [:]
            for attribute in attributes {
                if attribute.name.prefix == nil, attribute.name.localName == "xmlns" {
                    scope[""] = attribute.value
                } else if attribute.name.prefix == "xmlns" {
                    scope[attribute.name.localName] = attribute.value
                }
            }
            scopes.append(scope)

            let resolvedName = try resolveElement(name, at: mark)
            let resolvedAttributes = try attributes.map { try resolveAttribute($0, at: mark) }
            return (resolvedName, resolvedAttributes)
        }

        /// Closes an element, popping its scope.
        mutating func leaveElement() {
            if !scopes.isEmpty {
                scopes.removeLast()
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

        private func lookup(_ key: String) -> String? {
            for scope in scopes.reversed() {
                if let uri = scope[key] {
                    return uri.isEmpty ? nil : uri
                }
            }
            return nil
        }
    }
}
