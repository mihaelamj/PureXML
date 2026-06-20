extension PureXML.Schema.XSDParser {
    /// XSD 1.0 `src-resolve`, reduced to the part that holds even when no external
    /// document was loaded: a prefixed reference whose namespace is neither this
    /// schema's target namespace, the XSD or XML namespace, nor declared by any
    /// `xs:import` in the assembled set can resolve to no component, so it is
    /// unresolvable regardless. This runs only on the cross-document skip path.
    ///
    /// Soundness requires that the import closure be fully *known*. It is known only
    /// when every `import`/`include`/`redefine` is location-less: there is nothing to
    /// load, so no unseen document can transitively import a further namespace. The
    /// moment any external carries a `schemaLocation` that did not load, the closure is
    /// unknown (that document might import the very namespace a reference names, as in
    /// corpus schZ004, where the main doc imports only `a` but `a`'s document imports
    /// `b`, making `b:b` resolvable), so the whole check stands down to stay lenient.
    static func undeclaredNamespaceReferenceErrors(_ schema: XSDTree, containers: [XSDTree]) -> [String] {
        let sources = containers.isEmpty ? [schema] : containers
        if hasLocatedExternal(sources) { return [] }
        var declared: Set<String> = [xsdNamespace]
        declared.formUnion(unloadedReferenceNamespaces)
        for container in sources where PureXML.Schema.XSDNode.localName(container) == "schema" {
            if let target = PureXML.Schema.XSDNode.attribute(container, "targetNamespace"), !target.isEmpty {
                declared.insert(target)
            }
            for node in descendants(container, named: "import") where node.name?.namespaceURI == xsdNamespace {
                if let namespace = PureXML.Schema.XSDNode.attribute(node, "namespace"), !namespace.isEmpty {
                    declared.insert(namespace)
                }
            }
        }
        var errors: [String] = []
        for container in sources where PureXML.Schema.XSDNode.localName(container) == "schema" {
            collectUndeclaredNamespaceReferences(
                container,
                inheritedBindings: PureXML.Schema.XSDNode.namespaceBindings(of: container),
                declared: declared,
                into: &errors,
            )
        }
        return errors
    }

    private static func collectUndeclaredNamespaceReferences(
        _ node: XSDTree,
        inheritedBindings: [String: String],
        declared: Set<String>,
        into errors: inout [String],
    ) {
        let local = PureXML.Schema.XSDNode.localName(node)
        if local == "appinfo" || local == "documentation" { return }
        let bindings = mergedNamespaceBindings(on: node, inherited: inheritedBindings)
        if node.name?.namespaceURI == xsdNamespace {
            for qname in foreignReferenceQNames(of: node) {
                guard PureXML.Schema.XSDNode.prefix(qname.trimmingXMLWhitespace()) != nil,
                      let uri = referenceURI(for: qname, bindings: bindings), !uri.isEmpty,
                      !declared.contains(uri)
                else { continue }
                errors.append("reference to '\(qname)' names namespace '\(uri)', which is not the target namespace and is not imported")
            }
        }
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            collectUndeclaredNamespaceReferences(child, inheritedBindings: bindings, declared: declared, into: &errors)
        }
    }

    /// Whether any `import`/`include`/`redefine` carries a `schemaLocation`. On the
    /// skip path nothing was loaded, so a located external is one that failed to load,
    /// leaving the import closure (and thus resolvability) unknown.
    private static func hasLocatedExternal(_ sources: [XSDTree]) -> Bool {
        for container in sources where PureXML.Schema.XSDNode.localName(container) == "schema" {
            for kind in ["import", "include", "redefine"] {
                for node in descendants(container, named: kind) where node.name?.namespaceURI == xsdNamespace {
                    if let location = PureXML.Schema.XSDNode.attribute(node, "schemaLocation"), !location.isEmpty {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Every QName a node names through a resolving attribute: the single-QName
    /// `type`/`base`/`itemType`/`ref`/`substitutionGroup`, plus each token of a
    /// whitespace-separated `memberTypes`.
    private static func foreignReferenceQNames(of node: XSDTree) -> [String] {
        var references: [String] = []
        for attribute in ["type", "base", "itemType", "ref", "substitutionGroup"] {
            if let qname = PureXML.Schema.XSDNode.attribute(node, attribute) {
                references.append(qname)
            }
        }
        if let members = PureXML.Schema.XSDNode.attribute(node, "memberTypes") {
            references.append(contentsOf: members.split(whereSeparator: \.isWhitespace).map(String.init))
        }
        return references
    }
}
