private typealias XSDNode = PureXML.Schema.XSDNode
private typealias XSDContext = PureXML.Schema.XSDContext
private typealias Particle = PureXML.Schema.Particle
private typealias ComplexType = PureXML.Schema.ComplexType
private typealias ValueConstraint = PureXML.Schema.ValueConstraint
private typealias Compositor = PureXML.Schema.Compositor
private typealias ElementType = PureXML.Schema.ElementType
private typealias XSDSimpleParser = PureXML.Schema.XSDSimpleParser
private typealias BuiltinType = PureXML.Schema.BuiltinType
private typealias Wildcard = PureXML.Schema.Wildcard
private typealias Facets = PureXML.Schema.Facets
private typealias Group = PureXML.Schema.Group
private typealias SimpleType = PureXML.Schema.SimpleType
private typealias AttributeUse = PureXML.Schema.AttributeUse
private typealias XSDCompiled = PureXML.Schema.XSDCompiled

extension PureXML.Schema {
    /// Parses an XSD schema document into its global element declarations and its
    /// named-type table. Matches the schema vocabulary by local name, so the XML
    /// Schema namespace prefix may be anything. Supports global and local element
    /// declarations, named and inline simple and complex types, `sequence`,
    /// `choice`, and `all` model groups with occurrence, attribute uses, simple
    /// content, the full facet set, `list` and `union` simple types, named
    /// attribute groups and model groups, and element and group references.
    enum XSDParser {
        static func parse(_ xsd: String, loader: (String) -> String? = { _ in nil }) throws -> XSDCompiled {
            let root = try PureXML.parseTree(xsd)
            guard let schema = XSDNode.elementChildren(root).first(where: { XSDNode.localName($0) == "schema" }) else {
                throw PureXML.Schema.SchemaError.notASchema
            }
            var visited: Set<String> = []
            var rootLocation: String?
            let wrappedLoader: (String) -> String? = { location in
                let content = loader(location)
                if content == xsd {
                    rootLocation = location
                }
                return content
            }
            let containerTuples = XSDNode.collectContainers(schema, wrappedLoader, &visited)
            let containers = containerTuples.map(\.tree)
            let derivation = derivationTables(containers)
            try checkRedefine(containers)
            try checkAllGroups(containers)
            let containerLocations = containerLocationMap(containerTuples, rootLocation: rootLocation)
            let compositionLoaded = XSDNode.compositionLoaded(from: containerTuples)
            var context = createContext(
                schema: schema,
                containers: containers,
                derivation: derivation,
                containerLocations: containerLocations,
                compositionLoaded: compositionLoaded,
            )
            return finishCompile(schema: schema, containers: containers, derivation: derivation, context: &context)
        }
    }
}

extension PureXML.Schema.XSDParser {
    private static func containerLocationMap(
        _ containerTuples: [(location: String?, tree: XSDTree)],
        rootLocation: String?,
    ) -> [ObjectIdentifier: String?] {
        var containerLocations: [ObjectIdentifier: String?] = [:]
        for (loc, tree) in containerTuples {
            containerLocations[ObjectIdentifier(tree)] = loc ?? rootLocation
        }
        return containerLocations
    }

    private static func createContext(
        schema: XSDTree,
        containers: [XSDTree],
        derivation: DerivationTables,
        containerLocations: [ObjectIdentifier: String?],
        compositionLoaded: Bool,
    ) -> XSDContext {
        var context = XSDContext(
            simpleTypes: [:],
            attributeGroups: indexByName(allChildren(containers, named: "attributeGroup")),
            groups: indexByName(allChildren(containers, named: "group")),
            targetNamespace: XSDNode.attribute(schema, "targetNamespace"),
            substitutions: filterSubstitutions(XSDNode.substitutionMembers(containers), derivation),
            abstractElements: derivation.abstractElements,
            compositionLoaded: compositionLoaded,
            containerLocations: containerLocations,
        )
        context.elementFormQualified = XSDNode.attribute(schema, "elementFormDefault") == "qualified"
        context.attributeFormQualified = XSDNode.attribute(schema, "attributeFormDefault") == "qualified"
        context.namespaceBindings = XSDNode.namespaceBindings(of: schema)
        context.complexTypeNodes = indexByName(allChildren(containers, named: "complexType"))
        context.globalAttributes = indexByName(allChildren(containers, named: "attribute"))
        let redefinedAttributeGroups = PureXML.Schema.XSDParser.redefinedNames(containers, "attributeGroup")
        let redefinedGroups = PureXML.Schema.XSDParser.redefinedNames(containers, "group")
        let redefinedComplexTypes = PureXML.Schema.XSDParser.redefinedNames(containers, "complexType")
        context.redefinedAttributeGroups = redefinedAttributeGroups
        context.redefinedGroups = redefinedGroups
        context.redefinedComplexTypes = redefinedComplexTypes
        context.baseAttributeGroups = baseNamedComponents(containers, named: "attributeGroup")
        context.baseGroups = baseNamedComponents(containers, named: "group")
        context.baseComplexTypeNodes = baseNamedComponents(containers, named: "complexType")
        context.chameleonTargetNamespaces = chameleonTargetNamespaces(containers, locations: containerLocations)
        return context
    }

    private static func chameleonTargetNamespaces(
        _ containers: [XSDTree],
        locations: [ObjectIdentifier: String?],
    ) -> [ObjectIdentifier: String] {
        var map: [ObjectIdentifier: String] = [:]
        let schemas = containers.filter { XSDNode.localName($0) == "schema" }
        for included in schemas {
            let declared = XSDNode.attribute(included, "targetNamespace")
            guard declared == nil || declared?.isEmpty == true else { continue }
            guard let includedLocation = locations[ObjectIdentifier(included)] ?? nil else { continue }
            let includedBase = includedLocation.split(separator: "/").last.map(String.init) ?? includedLocation
            for parent in schemas where parent !== included {
                guard let parentNamespace = XSDNode.attribute(parent, "targetNamespace"), !parentNamespace.isEmpty else { continue }
                for child in XSDNode.elementChildren(parent) where XSDNode.localName(child) == "include" {
                    let href = XSDNode.attribute(child, "schemaLocation") ?? ""
                    if href == includedBase || includedLocation.hasSuffix(href) {
                        map[ObjectIdentifier(included)] = parentNamespace
                    }
                }
            }
        }
        return map
    }

    private struct CompiledBuild {
        var elements: [String: ElementType]
        var types: [String: ElementType]
        var globalAttributes: [String: AttributeUse]
        var containers: [XSDTree]
        var derivation: DerivationTables
        var context: XSDContext
        var identityFieldTypes: [String: SimpleType]
    }

    private static func finishCompile(
        schema: XSDTree,
        containers: [XSDTree],
        derivation: DerivationTables,
        context: inout XSDContext,
    ) -> XSDCompiled {
        for error in PureXML.Validation.SchemaCompile.preCompileErrors(schema: schema, context: context, containers: containers) {
            context.diagnostics.report(error)
        }
        seedElementNamespaces(containers, &context)
        var types = namedTypes(containers, into: &context)
        let elements = globalElements(containers, &context, into: &types)
        let globalAttributes = globalAttributeUses(containers, context)
        let postCompileDocument = PureXML.Schema.SchemaCompileContext(
            schema: schema,
            context: context,
            containers: containers,
            derivation: derivation,
            globalElements: elements,
            namedTypes: types,
        )
        for error in PureXML.Validation.SchemaCompile.postCompileErrors(in: postCompileDocument) {
            context.diagnostics.report(error)
        }
        return buildCompiled(CompiledBuild(
            elements: elements,
            types: types,
            globalAttributes: globalAttributes,
            containers: containers,
            derivation: derivation,
            context: context,
            identityFieldTypes: identityFieldTypes(containers, context),
        ))
    }

    private static func buildCompiled(_ build: CompiledBuild) -> XSDCompiled {
        let (nillable, elementConstraints) = elementMetadata(build.containers)
        return XSDCompiled(
            elements: build.elements,
            types: build.types,
            constraints: identityConstraints(build.containers),
            identityFieldTypes: build.identityFieldTypes,
            nillableElements: nillable,
            elementConstraints: elementConstraints,
            abstractTypes: build.derivation.abstractTypes,
            abstractElements: build.derivation.abstractElements,
            typeBlock: build.derivation.typeBlock,
            elementBlock: build.derivation.elementBlock,
            typeDerivation: build.derivation.typeDerivation,
            typeFinal: build.derivation.typeFinal,
            targetNamespace: build.context.targetNamespace,
            schemaErrors: build.context.diagnostics.deduplicated,
            globalAttributes: build.globalAttributes,
        )
    }

    private static func namedTypes(_ containers: [XSDTree], into context: inout XSDContext) -> [String: ElementType] {
        var types: [String: ElementType] = [:]
        for container in containers {
            let kind = XSDNode.localName(container)
            guard kind == "schema" || kind == "redefine" else { continue }
            var containerContext = scopedContext(from: context, container: container)
            let simpleTypeNodes = kind == "redefine"
                ? XSDNode.elementChildren(container).filter { XSDNode.localName($0) == "simpleType" }
                : XSDNode.children(container, named: "simpleType")
            resolveSimpleTypes(simpleTypeNodes, into: &containerContext)
            for (name, simple) in containerContext.simpleTypes {
                context.simpleTypes[name] = simple
                let compiled = ElementType.simple(simple)
                let key = typeDeclarationKey(name, namespaceURI: containerContext.targetNamespace)
                types[key] = compiled
                types[name] = compiled
            }
            let complexTypeNodes = kind == "redefine"
                ? XSDNode.elementChildren(container).filter { XSDNode.localName($0) == "complexType" }
                : XSDNode.children(container, named: "complexType")
            for node in complexTypeNodes {
                guard let name = XSDNode.attribute(node, "name") else { continue }
                let compiled = ElementType.complex(complexType(node, containerContext.visitingType(name)))
                let key = typeDeclarationKey(name, namespaceURI: containerContext.targetNamespace)
                types[key] = compiled
                types[name] = compiled
            }
        }
        return types
    }

    private static func scopedContext(from context: XSDContext, container: XSDTree) -> XSDContext {
        context.scoped(for: container)
    }

    /// Records each global element's target namespace before types are compiled,
    /// so substitution-group expansion during particle compilation sees the right
    /// namespace for imported members (for example `add:salutation` in ipo6).
    private static func seedElementNamespaces(_ containers: [XSDTree], _ context: inout XSDContext) {
        for container in containers where XSDNode.localName(container) == "schema" {
            let containerContext = scopedContext(from: context, container: container)
            for node in XSDNode.children(container, named: "element") {
                guard XSDNode.attribute(node, "name") != nil, XSDNode.attribute(node, "ref") == nil else { continue }
                let name = XSDNode.attribute(node, "name") ?? ""
                context.elementNamespaces[name] = containerContext.targetNamespace
            }
        }
    }

    private static func globalElements(
        _ containers: [XSDTree],
        _ context: inout XSDContext,
        into types: inout [String: ElementType],
    ) -> [String: ElementType] {
        var elements: [String: ElementType] = [:]
        for container in containers where XSDNode.localName(container) == "schema" {
            let containerContext = scopedContext(from: context, container: container)
            for node in XSDNode.children(container, named: "element") {
                guard XSDNode.attribute(node, "name") != nil, XSDNode.attribute(node, "ref") == nil else { continue }
                let name = XSDNode.attribute(node, "name") ?? ""
                context.elementNamespaces[name] = containerContext.targetNamespace
                let type = elementType(node, containerContext)
                elements[name] = type
                types[elementKey(name)] = type
                let qualified = PureXML.Model.QualifiedName(localName: name, namespaceURI: containerContext.targetNamespace)
                types[elementDeclarationKey(qualified)] = type
            }
        }
        return elements
    }

    private static func globalAttributeUses(
        _ containers: [XSDTree],
        _ context: XSDContext,
    ) -> [String: AttributeUse] {
        var attributes: [String: AttributeUse] = [:]
        for container in containers where XSDNode.localName(container) == "schema" {
            let containerContext = scopedContext(from: context, container: container)
            for node in XSDNode.children(container, named: "attribute") {
                guard XSDNode.attribute(node, "name") != nil, XSDNode.attribute(node, "ref") == nil,
                      var use = attributeUse(node, containerContext)
                else { continue }
                if let target = containerContext.targetNamespace, !target.isEmpty {
                    use.name = PureXML.Model.QualifiedName(localName: use.name.localName, namespaceURI: target)
                    let explicitTarget = XSDNode.attribute(container, "targetNamespace")
                    if explicitTarget == nil || explicitTarget?.isEmpty == true {
                        use.chameleonUnprefixed = true
                    }
                }
                attributes[attributeDeclarationKey(use.name)] = use
            }
        }
        return attributes
    }

    private static func allChildren(_ containers: [XSDTree], named name: String) -> [XSDTree] {
        containers.flatMap { XSDNode.children($0, named: name) }
    }

    /// Named component definitions from every container except `redefine`
    /// overlays, so a redefinition's self-reference resolves to the included
    /// definition rather than the overlay being built.
    private static func baseNamedComponents(_ containers: [XSDTree], named kind: String) -> [String: XSDTree] {
        var index: [String: XSDTree] = [:]
        for container in containers where XSDNode.localName(container) != "redefine" {
            for node in XSDNode.children(container, named: kind) {
                guard let name = XSDNode.attribute(node, "name") else { continue }
                index[name] = node
            }
        }
        return index
    }

    /// Resolves the named simple types into `context` over repeated passes:
    /// named simple types may restrict or list one another regardless of
    /// document order, so each pass sees the types the previous one resolved. A
    /// dependency chain of length n settles in at most n passes.
    private static func resolveSimpleTypes(_ nodes: [XSDTree], into context: inout XSDContext) {
        let named = nodes.filter { XSDNode.attribute($0, "name") != nil }
        for _ in named.indices {
            for node in named {
                if let name = XSDNode.attribute(node, "name") {
                    context.simpleTypes[name] = XSDSimpleParser.simpleType(node, context)
                }
            }
        }
    }

    // MARK: Complex types

    static func complexType(_ node: XSDTree, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.ComplexType {
        let mixed = XSDNode.attribute(node, "mixed").map { $0 == "true" || $0 == "1" } ?? false
        let attributes = attributeUses(under: node, context)
        if let simpleContent = XSDNode.firstChild(node, named: "simpleContent") {
            let inner = derivation(simpleContent)
            let wildcard = inner.flatMap { attributeWildcard(under: $0, context) }
            let derived = inner.map { PureXML.Schema.XSDParser.simpleContentAttributes(under: $0, context) } ?? []
            return ComplexType(
                attributes: attributes + derived,
                attributeWildcard: wildcard,
                content: .simpleContent(simpleContentType(simpleContent, context)),
            )
        }
        if let complexContent = XSDNode.firstChild(node, named: "complexContent"), let inner = derivation(complexContent) {
            return complexContentType(inner, mixed: mixed || XSDNode.attribute(complexContent, "mixed").map { $0 == "true" || $0 == "1" } ?? false, context)
        }
        let wildcard = attributeWildcard(under: node, context)
        guard let particle = modelGroup(in: node, context) else {
            // A mixed type with no content model still permits character data
            // (just no child elements): mixed content over an empty particle,
            // not the empty content type, which forbids text.
            guard mixed else {
                return ComplexType(attributes: attributes, attributeWildcard: wildcard, content: .empty)
            }
            let emptyParticle = Particle(term: .group(.init(compositor: .sequence, particles: [])))
            return ComplexType(attributes: attributes, attributeWildcard: wildcard, content: .mixed(emptyParticle))
        }
        return ComplexType(attributes: attributes, attributeWildcard: wildcard, content: mixed ? .mixed(particle) : .elementOnly(particle))
    }

    private static func simpleContentType(_ node: XSDTree, _ context: XSDContext) -> SimpleType {
        guard let inner = derivation(node) else { return SimpleType(base: .string) }
        let rawBase = XSDNode.attribute(inner, "base") ?? "string"
        let baseName = XSDNode.stripPrefix(rawBase)
        let bindings = PureXML.Schema.XSDParser.namespaceBindingsInScope(of: inner, defaultBindings: context.namespaceBindings)
        let uri = XSDNode.referenceNamespace(rawBase, bindings)

        let base: BuiltinType
        let inheritedFacets: Facets
        if uri == PureXML.Schema.XSDParser.xsdNamespace {
            base = BuiltinType(rawValue: baseName) ?? .string
            inheritedFacets = Facets()
        } else {
            base = context.simpleTypes[baseName]?.base ?? .string
            inheritedFacets = context.simpleTypes[baseName]?.facets ?? Facets()
        }
        var facets = inheritedFacets
        XSDSimpleParser.applyFacets(inner, into: &facets)
        return SimpleType(base: base, facets: facets)
    }
}
