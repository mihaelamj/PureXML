private typealias SubTypeNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// XSD 1.0 `e-props-correct.4`: the {type definition} of an element declaration
    /// must be validly derived from the {type definition} of the head of every
    /// substitution group it affiliates to (any type derives from the head's
    /// ur-type, so an untyped head admits any member). A member whose type is
    /// unrelated to the head's, for instance an element of type `xs:int` declaring
    /// `substitutionGroup` of a head typed `xs:string`, leaves the schema wrongly
    /// accepted.
    ///
    /// Scope and conservatism:
    /// - Checked only for a self-contained schema (no `import`/`include`/`redefine`),
    ///   where the derivation table is complete and, with one target namespace, the
    ///   names resolved by local name are unambiguous.
    /// - The member's type is read from its own `type` attribute and the head's from
    ///   a map of the top-level (global) element declarations only, so a local
    ///   element sharing a name does not supply either type.
    /// - `typeDerivesOrEqual` models the restriction/extension chain and the built-in
    ///   lattice but not the list/union variety rules (`cos-st-derived-ok` clauses
    ///   2.3 and 2.4: a type derives from a union if it derives from one of the
    ///   union's member types). When either type is a list or union the check stands
    ///   down rather than reject a valid member, a disclosed under-rejection.
    static func substitutionTypeFindings(
        _ schema: XSDTree,
        _ containers: [XSDTree],
        _ tables: DerivationTables,
        _ types: [String: PureXML.Schema.ElementType],
        _ context: PureXML.Schema.XSDContext,
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let sources = context.compositionLoaded ? containers : [schema]
        let namespaceMap = resolveContainerNamespaces(containers, mainTargetNamespace: context.targetNamespace)
        var globalElementType: [GlobalElementKey: String] = [:]
        for index in sources.indices {
            let source = sources[index]
            guard SubTypeNode.localName(source) != "redefine" else { continue }
            let namespaceURI = context.compositionLoaded
                ? (namespaceMap[index] ?? context.targetNamespace)
                : context.targetNamespace
            for global in SubTypeNode.elementChildren(source).filter({
                SubTypeNode.localName($0) == "element" && $0.name?.namespaceURI == xsdNamespace
            }) {
                if let name = SubTypeNode.attribute(global, "name"), let type = SubTypeNode.attribute(global, "type") {
                    globalElementType[GlobalElementKey(namespaceURI: namespaceURI, name: name)] = SubTypeNode.stripPrefix(type)
                }
            }
        }
        return sources.indices.flatMap { index -> [PureXML.Schema.SchemaLocatedFinding] in
            let source = sources[index]
            guard SubTypeNode.localName(source) != "redefine" else { return [] }
            let bindings = SubTypeNode.namespaceBindings(of: source)
            return SubTypeNode.elementChildren(source).filter {
                SubTypeNode.localName($0) == "element" && $0.name?.namespaceURI == xsdNamespace
            }.flatMap { element in
                checkSingleElement(element, bindings, globalElementType, tables, types)
            }
        }
    }

    private struct GlobalElementKey: Hashable {
        let namespaceURI: String?
        let name: String
    }

    private static func checkSingleElement(
        _ element: XSDTree,
        _ bindings: [String: String],
        _ globalElementType: [GlobalElementKey: String],
        _ tables: DerivationTables,
        _ types: [String: PureXML.Schema.ElementType],
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        guard let member = SubTypeNode.attribute(element, "name"),
              let headReference = SubTypeNode.attribute(element, "substitutionGroup")
        else { return [] }
        let head = SubTypeNode.stripPrefix(headReference)
        let headNamespace = SubTypeNode.referenceNamespace(headReference, bindings)
        let headKey = GlobalElementKey(namespaceURI: headNamespace, name: head)
        guard let headType = globalElementType[headKey] else { return [] }
        if isInlineListOrUnion(element) { return [] }
        let inlineDeriv = inlineTypeDerivation(element)
        var isDerived: Bool
        let memberType: String
        if let inlineDeriv {
            memberType = "anonymous"
            isDerived = inlineDeriv.base == headType || PureXML.Schema.ParticleRestriction.typeDerivesOrEqual(inlineDeriv.base, headType, tables.typeDerivation, types)
        } else if let typeAttr = SubTypeNode.attribute(element, "type").map(SubTypeNode.stripPrefix) {
            memberType = typeAttr
            isDerived = PureXML.Schema.ParticleRestriction.typeDerivesOrEqual(memberType, headType, tables.typeDerivation, types)
        } else {
            // A member without its own type uses the substitution head's type definition.
            memberType = headType
            isDerived = true
        }
        if isBuiltinAnySimpleType(headType, types) {
            isDerived = inlineMemberHasSimpleContent(element) ?? memberTypeHasSimpleContent(memberType, types) ?? isDerived
        }
        // A member whose type is a list or union derives only from anySimpleType, so
        // it may affiliate only to a head typed anySimpleType (or to the same type, or
        // as a recorded restriction of the head's type, both of which `isDerived`
        // covers). Affiliating it to any other head type is not a valid derivation.
        if isListOrUnion(memberType, types), !isDerived, headType != "anySimpleType", headType != "anyType" {
            return [
                PureXML.Schema.SchemaLocatedFinding(
                    reason: "element '\(member)' may not be in the substitution group of '\(head)': its list or union type is not derived from '\(headType)'",
                    node: element,
                ),
            ]
        }
        guard !isListOrUnion(memberType, types), !isListOrUnion(headType, types) else { return [] }
        if !isDerived {
            return [
                PureXML.Schema.SchemaLocatedFinding(
                    reason: "element '\(member)' may not be in the substitution group of '\(head)': its type is not derived from '\(headType)'",
                    node: element,
                ),
            ]
        }
        return checkExclusions(
            member: member,
            memberType: memberType,
            inlineDeriv: inlineDeriv,
            headInfo: (head, headType),
            tables: tables,
        ).map { PureXML.Schema.SchemaLocatedFinding(reason: $0, node: element) }
    }

    private static func checkExclusions(
        member: String,
        memberType: String,
        inlineDeriv: PureXML.Schema.TypeDerivation?,
        headInfo: (head: String, headType: String),
        tables: DerivationTables,
    ) -> [String] {
        guard let exclusions = tables.elementFinal[headInfo.head] else { return [] }
        var errors: [String] = []
        var pathMethods: Set<PureXML.Schema.DerivationMethod> = []
        var currentType: String
        if let inlineDeriv {
            pathMethods.insert(inlineDeriv.method)
            currentType = inlineDeriv.base
        } else {
            currentType = memberType
        }
        var visited: Set<String> = [currentType]
        while currentType != headInfo.headType {
            guard let derivation = tables.typeDerivation[currentType] else {
                break
            }
            pathMethods.insert(derivation.method)
            guard visited.insert(derivation.base).inserted else {
                break
            }
            currentType = derivation.base
        }
        if currentType != headInfo.headType {
            let member = PureXML.Schema.BuiltinType(rawValue: currentType)
            let head = PureXML.Schema.BuiltinType(rawValue: headInfo.headType)
            if let member, let head, member.derives(from: head) {
                pathMethods.insert(.restriction)
            }
        }
        if exclusions.contains(.extension), pathMethods.contains(.extension) {
            errors.append(
                "element '\(member)' may not be in the substitution group of '\(headInfo.head)': "
                    + "its type '\(memberType)' is derived by extension from '\(headInfo.headType)' which is excluded by the head element",
            )
        }
        if exclusions.contains(.restriction), pathMethods.contains(.restriction) {
            errors.append(
                "element '\(member)' may not be in the substitution group of '\(headInfo.head)': "
                    + "its type '\(memberType)' is derived by restriction from '\(headInfo.headType)' which is excluded by the head element",
            )
        }
        return errors
    }

    private static func inlineTypeDerivation(_ element: XSDTree) -> PureXML.Schema.TypeDerivation? {
        if let complex = SubTypeNode.elementChildren(element).first(where: {
            $0.name?.namespaceURI == xsdNamespace && SubTypeNode.localName($0) == "complexType"
        }) {
            if let info = derivationInfo(complex) {
                return info
            }
            return PureXML.Schema.TypeDerivation(base: "anyType", method: .restriction)
        }
        if let simple = SubTypeNode.elementChildren(element).first(where: {
            $0.name?.namespaceURI == xsdNamespace && SubTypeNode.localName($0) == "simpleType"
        }) {
            return simpleTypeNodeDerivation(simple)
        }
        return nil
    }

    private static func simpleTypeNodeDerivation(_ simple: XSDTree) -> PureXML.Schema.TypeDerivation? {
        if let restriction = SubTypeNode.elementChildren(simple).first(where: {
            $0.name?.namespaceURI == xsdNamespace && SubTypeNode.localName($0) == "restriction"
        }) {
            if let base = SubTypeNode.attribute(restriction, "base") {
                return PureXML.Schema.TypeDerivation(base: SubTypeNode.stripPrefix(base), method: .restriction)
            }
            if let inlineBase = SubTypeNode.elementChildren(restriction).first(where: {
                $0.name?.namespaceURI == xsdNamespace && SubTypeNode.localName($0) == "simpleType"
            }) {
                return simpleTypeNodeDerivation(inlineBase)
            }
        }
        return PureXML.Schema.TypeDerivation(base: "anySimpleType", method: .restriction)
    }

    private static func isInlineListOrUnion(_ element: XSDTree) -> Bool {
        guard let simple = SubTypeNode.elementChildren(element).first(where: {
            $0.name?.namespaceURI == xsdNamespace && SubTypeNode.localName($0) == "simpleType"
        }) else { return false }
        return isSimpleNodeListOrUnion(simple)
    }

    private static func isSimpleNodeListOrUnion(_ simple: XSDTree) -> Bool {
        if SubTypeNode.elementChildren(simple).contains(where: {
            let local = SubTypeNode.localName($0)
            return $0.name?.namespaceURI == xsdNamespace && (local == "list" || local == "union")
        }) {
            return true
        }
        if let restriction = SubTypeNode.elementChildren(simple).first(where: {
            $0.name?.namespaceURI == xsdNamespace && SubTypeNode.localName($0) == "restriction"
        }) {
            if let inlineBase = SubTypeNode.elementChildren(restriction).first(where: {
                $0.name?.namespaceURI == xsdNamespace && SubTypeNode.localName($0) == "simpleType"
            }) {
                return isSimpleNodeListOrUnion(inlineBase)
            }
        }
        return false
    }

    /// Whether the named type is a list- or union-variety simple type, whose
    /// derivation rules `typeDerivesOrEqual` does not model. A built-in or unknown
    /// name is treated as atomic.
    private static func isListOrUnion(_ name: String, _ types: [String: PureXML.Schema.ElementType]) -> Bool {
        guard case let .simple(simple)? = types[name] else { return false }
        switch simple.variety {
        case .atomic: return false
        case .list, .union: return true
        }
    }

    private static func isBuiltinAnySimpleType(_ name: String, _ types: [String: PureXML.Schema.ElementType]) -> Bool {
        name == "anySimpleType" && types[name] == nil
    }

    /// Whether a member type can derive from the simple ur-type. Unknown types are
    /// left undecided so the reference-resolution rule, not this check, owns them.
    private static func memberTypeHasSimpleContent(_ name: String, _ types: [String: PureXML.Schema.ElementType]) -> Bool? {
        if name == "anySimpleType" { return true }
        if name == "anyType" { return false }
        if PureXML.Schema.BuiltinType(rawValue: name) != nil { return true }
        var current: PureXML.Schema.ElementType? = types[name]
        var steps = 0
        while let resolved = current, steps <= types.count {
            switch resolved {
            case .simple:
                return true
            case let .complex(complex):
                if case .simpleContent = complex.content { return true }
                return false
            case let .typeReference(key):
                current = types[key]
                steps += 1
            }
        }
        return nil
    }

    private static func inlineMemberHasSimpleContent(_ element: XSDTree) -> Bool? {
        if SubTypeNode.elementChildren(element).contains(where: {
            $0.name?.namespaceURI == xsdNamespace && SubTypeNode.localName($0) == "simpleType"
        }) {
            return true
        }
        guard let complex = SubTypeNode.elementChildren(element).first(where: {
            $0.name?.namespaceURI == xsdNamespace && SubTypeNode.localName($0) == "complexType"
        }) else { return nil }
        return SubTypeNode.firstChild(complex, named: "simpleContent") != nil
    }
}
