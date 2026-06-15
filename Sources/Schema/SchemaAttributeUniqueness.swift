private typealias AttrNode = PureXML.Schema.XSDNode

/// One reached attribute declaration: the identity of its declaring node (so the
/// same declaration reached by two paths is one), its resolved name, and whether
/// its type is ID-derived.
private struct ReachedAttribute {
    let id: ObjectIdentifier
    let name: PureXML.Model.QualifiedName
    let isID: Bool
}

extension PureXML.Schema.XSDParser {
    /// Schema-validity findings for attribute-use uniqueness (XSD 1.0
    /// `ct-props-correct.4` / `ag-props-correct.2`) and the single-ID rule
    /// (`ct-props-correct.5`): a complex type's or attribute group's complete
    /// attribute-use set may not contain two distinct declarations whose names and
    /// namespaces match, nor more than one attribute whose type is (or derives
    /// from) `xs:ID`.
    ///
    /// The set is flattened through `attributeGroup` references and declarations are
    /// deduplicated by identity, so the same declaration reached by two paths (a
    /// diamond of attribute-group references) counts once, not as a clash. Names
    /// carry their resolved namespace, so a qualified and an unqualified attribute
    /// of the same local name do not collide. The own-declared set is checked, not
    /// the set inherited through extension (a disclosed under-rejection).
    static func attributeUseErrors(_ containers: [XSDTree], _ context: PureXML.Schema.XSDContext) -> [String] {
        var errors: [String] = []
        for container in containers {
            for group in descendants(container, named: "attributeGroup") {
                guard let name = AttrNode.attribute(group, "name") else { continue }
                errors += attributeSetErrors(attributeDeclarations(under: group, context), "attribute group '\(name)'")
            }
            for type in descendants(container, named: "complexType") {
                let label = AttrNode.attribute(type, "name").map { "complex type '\($0)'" } ?? "an anonymous complex type"
                errors += attributeSetErrors(attributeDeclarations(under: attributeContainer(of: type), context), label)
            }
        }
        return errors
    }

    /// The node whose direct children declare a complex type's attributes: the
    /// `complexContent`/`simpleContent` derivation when present, else the type
    /// itself (the shorthand form).
    private static func attributeContainer(of type: XSDTree) -> XSDTree {
        guard let derivation = AttrNode.firstChild(type, named: "complexContent") ?? AttrNode.firstChild(type, named: "simpleContent"),
              let body = AttrNode.firstChild(derivation, named: "extension") ?? AttrNode.firstChild(derivation, named: "restriction")
        else {
            return type
        }
        return body
    }

    /// Each attribute declaration reachable under `node`, paired with the identity
    /// of its declaring node (a `ref` resolves to the one global declaration, so two
    /// references to it share identity), its resolved name, and whether its type is
    /// ID-derived.
    private static func attributeDeclarations(under node: XSDTree, _ context: PureXML.Schema.XSDContext, visited: Set<String> = []) -> [ReachedAttribute] {
        var result: [ReachedAttribute] = []
        for child in AttrNode.elementChildren(node) {
            switch AttrNode.localName(child) {
            case "attribute":
                if let ref = AttrNode.attribute(child, "ref") {
                    let refName = AttrNode.stripPrefix(ref)
                    guard let declaration = context.globalAttributes[refName], let use = attributeUse(declaration, context) else { break }
                    // The reference's namespace is its prefix's binding (an imported
                    // attribute is in the imported namespace), not the target namespace,
                    // so `a` and `imp:a` are different attributes, not a clash.
                    let namespace = AttrNode.referenceNamespace(ref, context.namespaceBindings)
                    result.append(ReachedAttribute(
                        id: ObjectIdentifier(declaration),
                        name: PureXML.Model.QualifiedName(localName: refName, namespaceURI: namespace),
                        isID: use.type.base == .id,
                    ))
                } else if let use = attributeUse(child, context) {
                    result.append(ReachedAttribute(id: ObjectIdentifier(child), name: use.name, isID: use.type.base == .id))
                }
            case "attributeGroup":
                guard let ref = AttrNode.attribute(child, "ref") else { break }
                let name = AttrNode.stripPrefix(ref)
                guard !visited.contains(name), let group = context.attributeGroups[name] else { break }
                result += attributeDeclarations(under: group, context, visited: visited.union([name]))
            default:
                break
            }
        }
        return result
    }

    private static func attributeSetErrors(_ declarations: [ReachedAttribute], _ label: String) -> [String] {
        var seenIDs: Set<ObjectIdentifier> = []
        var counts: [PureXML.Model.QualifiedName: Int] = [:]
        var idCount = 0
        for declaration in declarations where seenIDs.insert(declaration.id).inserted {
            counts[declaration.name, default: 0] += 1
            if declaration.isID { idCount += 1 }
        }
        var errors: [String] = []
        for name in counts.keys.sorted(by: { ($0.localName, $0.namespaceURI ?? "") < ($1.localName, $1.namespaceURI ?? "") }) where (counts[name] ?? 0) > 1 {
            errors.append("\(label) has more than one attribute named '\(name.localName)'")
        }
        if idCount > 1 {
            errors.append("\(label) has more than one attribute of type ID")
        }
        return errors
    }
}
