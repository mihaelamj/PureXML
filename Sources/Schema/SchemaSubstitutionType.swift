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
    static func substitutionTypeErrors(_ schema: XSDTree, _ tables: DerivationTables, _ types: [String: PureXML.Schema.ElementType]) -> [String] {
        guard !hasExternalDocuments(schema) else { return [] }
        let globals = SubTypeNode.elementChildren(schema).filter {
            SubTypeNode.localName($0) == "element" && $0.name?.namespaceURI == xsdNamespace
        }
        var globalElementType: [String: String] = [:]
        for global in globals {
            if let name = SubTypeNode.attribute(global, "name"), let type = SubTypeNode.attribute(global, "type") {
                globalElementType[name] = SubTypeNode.stripPrefix(type)
            }
        }
        return globals.flatMap { element in
            checkSingleElement(element, globalElementType, tables, types)
        }
    }

    private static func checkSingleElement(
        _ element: XSDTree,
        _ globalElementType: [String: String],
        _ tables: DerivationTables,
        _ types: [String: PureXML.Schema.ElementType],
    ) -> [String] {
        guard let member = SubTypeNode.attribute(element, "name"),
              let headReference = SubTypeNode.attribute(element, "substitutionGroup")
        else { return [] }
        let head = SubTypeNode.stripPrefix(headReference)
        guard let headType = globalElementType[head] else { return [] }
        if isInlineListOrUnion(element) { return [] }
        let inlineDeriv = inlineTypeDerivation(element)
        let isDerived: Bool
        let memberType: String
        if let inlineDeriv {
            memberType = "anonymous"
            isDerived = inlineDeriv.base == headType || PureXML.Schema.ParticleRestriction.typeDerivesOrEqual(inlineDeriv.base, headType, tables.typeDerivation, types)
        } else if let typeAttr = SubTypeNode.attribute(element, "type").map(SubTypeNode.stripPrefix) {
            memberType = typeAttr
            isDerived = PureXML.Schema.ParticleRestriction.typeDerivesOrEqual(memberType, headType, tables.typeDerivation, types)
        } else {
            memberType = headType
            isDerived = true
        }
        guard !isListOrUnion(memberType, types), !isListOrUnion(headType, types) else { return [] }
        if !isDerived {
            return ["element '\(member)' may not be in the substitution group of '\(head)': its type is not derived from '\(headType)'"]
        }
        return checkExclusions(
            member: member,
            memberType: memberType,
            inlineDeriv: inlineDeriv,
            headInfo: (head, headType),
            tables: tables,
        )
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

    /// Whether the schema document composes other documents, so a referenced
    /// definition may live outside the loaded derivation table.
    private static func hasExternalDocuments(_ schema: XSDTree) -> Bool {
        SubTypeNode.elementChildren(schema).contains { child in
            let kind = SubTypeNode.localName(child)
            return kind == "import" || kind == "include" || kind == "redefine"
        }
    }
}
