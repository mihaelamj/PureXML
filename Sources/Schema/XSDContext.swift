/// A schema-document tree node.
typealias XSDTree = PureXML.Model.TreeNode

extension PureXML.Schema {
    /// Tree-access helpers and document collection shared by the schema parser
    /// across its files.
    enum XSDNode {
        static func localName(_ node: XSDTree) -> String? {
            node.name?.localName
        }

        static func attribute(_ node: XSDTree, _ name: String) -> String? {
            node.attributes.first { $0.name.localName == name }?.value
        }

        static func elementChildren(_ node: XSDTree) -> [XSDTree] {
            node.children.filter { $0.kind == .element }
        }

        static func children(_ node: XSDTree, named name: String) -> [XSDTree] {
            elementChildren(node).filter { localName($0) == name }
        }

        static func firstChild(_ node: XSDTree, named name: String) -> XSDTree? {
            children(node, named: name).first
        }

        /// The enclosing `schema` element for a component node or container.
        static func schemaOwner(_ node: XSDTree) -> XSDTree {
            var current: XSDTree? = node
            while let element = current {
                if localName(element) == "schema" { return element }
                current = element.parent
            }
            return node
        }

        static func stripPrefix(_ qualified: String) -> String {
            qualified.split(separator: ":").last.map(String.init) ?? qualified
        }

        /// The prefix part of a QName (`p` in `p:local`), or nil when unprefixed.
        static func prefix(_ qualified: String) -> String? {
            let parts = qualified.split(separator: ":", maxSplits: 1)
            return parts.count == 2 ? String(parts[0]) : nil
        }

        /// The namespace prefix bindings declared on a schema-root element:
        /// `xmlns:p="..."` keyed by `p`, the default `xmlns="..."` under the empty key.
        static func namespaceBindings(of schema: XSDTree) -> [String: String] {
            var bindings: [String: String] = [:]
            for attribute in schema.attributes {
                if attribute.name.prefix == "xmlns" {
                    bindings[attribute.name.localName] = attribute.value
                } else if attribute.name.prefix == nil, attribute.name.localName == "xmlns" {
                    bindings[""] = attribute.value
                }
            }
            return bindings
        }

        /// The namespace URI a reference QName resolves to, given the schema's prefix
        /// bindings: a prefixed name uses its prefix's binding, an unprefixed name the
        /// default-namespace binding (nil when none is declared).
        static func referenceNamespace(_ qualified: String, _ bindings: [String: String]) -> String? {
            if let prefix = prefix(qualified) {
                if prefix == "xml" { return "http://www.w3.org/XML/1998/namespace" }
                return bindings[prefix]
            }
            return bindings[""]
        }

        /// The namespace of a schema-local unprefixed QName: the default-namespace
        /// binding when declared, otherwise the schema `targetNamespace`.
        static func schemaComponentNamespace(_ qualified: String, _ bindings: [String: String], targetNamespace: String?) -> String? {
            if prefix(qualified) != nil {
                return referenceNamespace(qualified, bindings)
            }
            if let defaultNamespace = bindings[""] {
                return defaultNamespace
            }
            return targetNamespace
        }

        static func occurrence(_ node: XSDTree) -> (min: Int, max: Int?) {
            let minimum = attribute(node, "minOccurs").flatMap(Int.init) ?? 1
            let maximumText = attribute(node, "maxOccurs")
            let maximum: Int? = maximumText == "unbounded" ? nil : (maximumText.flatMap(Int.init) ?? 1)
            return (minimum, maximum)
        }

        /// Collects the schema's own element and a transitive closure of the
        /// schemas it pulls in through `include`, `import`, and `redefine`
        /// (resolved through `loader` by `schemaLocation`), base schemas first so
        /// the including schema's definitions take precedence. A `redefine`
        /// element is itself returned as a container so its nested redefinitions
        /// override the schema it includes.
        static func collectContainers(
            _ schema: XSDTree,
            _ loader: (String) -> String?,
            _ visited: inout Set<String>,
            currentLocation: String? = nil,
        ) -> [(location: String?, tree: XSDTree)] {
            var containers: [(location: String?, tree: XSDTree)] = []
            for child in elementChildren(schema) {
                let kind = localName(child)
                guard kind == "include" || kind == "import" || kind == "redefine",
                      let location = attribute(child, "schemaLocation"), !visited.contains(location)
                else {
                    continue
                }
                visited.insert(location)
                let sub = loader(location).flatMap { try? PureXML.parseTree($0) }
                    .flatMap { root in elementChildren(root).first { localName($0) == "schema" } }
                if let sub {
                    containers += collectContainers(sub, loader, &visited, currentLocation: location)
                }
                if kind == "redefine" {
                    containers.append((location: location, tree: child))
                }
            }
            containers.append((location: currentLocation, tree: schema))
            return containers
        }

        /// src-include.1 / src-import.1.2 / src-redefine: when an
        /// `include`/`import`/`redefine` `schemaLocation` IS resolved (the loader
        /// returns content), that content must be a well-formed schema document. A
        /// location the loader does not resolve (returns nil) is not an error, since
        /// resolution is the processor's choice. Mirrors `collectContainers`' walk,
        /// recursing through resolved documents, cycle-guarded by `visited`. Returns
        /// every location whose resolved content is not a schema, for a validation to
        /// report; it does not throw, so the finding flows through the validator.
        static func failedSchemaReferences(
            _ schema: XSDTree,
            _ loader: (String) -> String?,
            _ visited: inout Set<String>,
        ) -> [String] {
            var failures: [String] = []
            for child in elementChildren(schema) {
                let kind = localName(child)
                guard kind == "include" || kind == "import" || kind == "redefine",
                      let location = attribute(child, "schemaLocation"), !visited.contains(location)
                else { continue }
                visited.insert(location)
                guard let content = loader(location) else { continue }
                guard let root = try? PureXML.parseTree(content),
                      let sub = elementChildren(root).first(where: { localName($0) == "schema" })
                else {
                    failures.append(location)
                    continue
                }
                failures += failedSchemaReferences(sub, loader, &visited)
            }
            return failures
        }

        /// True when at least one external schema document was loaded (not merely
        /// referenced or a `redefine` wrapper without its included target).
        static func compositionLoaded(from containerTuples: [(location: String?, tree: XSDTree)]) -> Bool {
            containerTuples.contains { tuple in
                tuple.location != nil && localName(tuple.tree) == "schema"
            }
        }
    }

    /// The result of compiling a schema document: its global element
    /// declarations, its named-type table, and the identity constraints declared
    /// on each element name.
    struct XSDCompiled {
        var elements: [String: ElementType]
        var types: [String: ElementType]
        var constraints: [String: [IdentityConstraint]]
        /// Simple types for identity-constraint field paths.
        var identityFieldTypes: [String: SimpleType] = [:]
        /// `default`/`fixed` value constraints on identity-constraint field
        /// targets, so an absent attribute or empty element takes that value as its
        /// identity-tuple component.
        var identityFieldConstraints: [String: ValueConstraint] = [:]
        /// Local names of elements declared `nillable="true"`.
        var nillableElements: Set<String> = []
        /// The `default`/`fixed` value constraint declared on each element name.
        var elementConstraints: [String: ValueConstraint] = [:]
        /// Local names of complex types declared `abstract="true"`. Bare-keyed, for
        /// the schema-consistency rules and direct unit tests.
        var abstractTypes: Set<String> = []
        /// Local names of element declarations declared `abstract="true"`: they may
        /// not appear in an instance directly, only through a substitution member.
        var abstractElements: Set<String> = []
        /// Derivation methods the named type forbids when used through `xsi:type`.
        /// Bare-keyed.
        var typeBlock: [String: Set<DerivationMethod>] = [:]
        /// Derivation methods each element declaration forbids through `xsi:type`.
        /// Bare-keyed.
        var elementBlock: [String: Set<DerivationMethod>] = [:]
        /// Each named complex type's base type and derivation method, the backbone
        /// the schema-consistency rules walk. Bare-keyed.
        var typeDerivation: [String: TypeDerivation] = [:]
        /// Namespaced (`{ns}local`) views of the abstract-type set, `block` tables,
        /// and derivation backbone, for the INSTANCE-validity subsystem, where two
        /// imported types sharing a local name in different namespaces must not
        /// collide.
        var nsAbstractTypes: Set<String> = []
        var nsTypeBlock: [String: Set<DerivationMethod>] = [:]
        var nsElementBlock: [String: Set<DerivationMethod>] = [:]
        var nsTypeDerivation: [String: TypeDerivation] = [:]
        /// Derivation methods each named type declares `final`, for the
        /// schema-consistency rules.
        var typeFinal: [String: Set<DerivationMethod>] = [:]
        /// The schema's target namespace, so the root element's namespace can be
        /// checked against it.
        var targetNamespace: String?
        /// Schema-validity findings gathered while parsing (malformed facet
        /// definitions and the like), reported together with the model-level
        /// consistency findings when the schema is compiled.
        var schemaErrors: [PureXML.Validation.ValidationError] = []
        /// Global attribute declarations keyed by ``attributeDeclarationKey(_:)``.
        var globalAttributes: [String: AttributeUse] = [:]
    }

    /// Collects the located findings of simple-type facet and pattern validity,
    /// which are computed during type compilation (they need the resolved base
    /// type) and surfaced by the `simpleTypeFacetsAreValid` validation rather than
    /// reported straight to `diagnostics`. A reference type so the findings survive
    /// the value-type ``XSDContext``'s copies.
    final class CompileFindingSink {
        private(set) var findings: [PureXML.Schema.SchemaLocatedFinding] = []

        func add(_ reason: String, at node: PureXML.Model.TreeNode) {
            findings.append(PureXML.Schema.SchemaLocatedFinding(reason: reason, node: node))
        }
    }

    /// Collects schema-validity findings during parsing. A reference type so the
    /// findings survive the value-type ``XSDContext``'s copies (`visiting(_:)`):
    /// every copy shares the one collector, and the parser harvests it at the end.
    final class SchemaDiagnostics {
        private(set) var errors: [PureXML.Validation.ValidationError] = []

        func report(_ error: PureXML.Validation.ValidationError) {
            errors.append(error)
        }

        func report(_ reason: String, at node: PureXML.Model.TreeNode?) {
            report(PureXML.Validation.ValidationError(
                reason: reason,
                at: node?.validationCodingPath() ?? [.element("schema")],
            ))
        }

        /// The findings with exact-duplicate messages removed, first occurrence
        /// kept. The same malformed definition is visited more than once (named
        /// simple types resolve over repeated passes), so dedup keeps one finding
        /// per distinct problem.
        var deduplicated: [PureXML.Validation.ValidationError] {
            var seen: Set<String> = []
            return errors.filter {
                let key = "\(PureXML.Validation.PathKey.render($0.codingPath))|\($0.reason)"
                return seen.insert(key).inserted
            }
        }
    }

    /// The parsing context: the named simple types resolved so far, plus the
    /// definition nodes for named attribute groups and model groups (so their
    /// refs can be expanded), and a guard against cyclic group references.
    struct XSDContext {
        var simpleTypes: [String: SimpleType]
        var attributeGroups: [String: XSDTree]
        /// Attribute-group definitions from included schemas before a `redefine`
        /// overlay replaces them; used when a redefinition self-references its
        /// former self.
        var baseAttributeGroups: [String: XSDTree] = [:]
        /// Names of attribute groups redefined through `xs:redefine`.
        var redefinedAttributeGroups: Set<String> = []
        /// Top-level (global) attribute declaration nodes by name, so an
        /// `<attribute ref="...">` resolves to the global declaration's type.
        var globalAttributes: [String: XSDTree] = [:]
        /// Top-level (global) element declaration nodes keyed by namespaced
        /// component identity (`{namespace}local`), so an `<element ref="...">`
        /// particle can carry the referenced declaration's type and metadata into
        /// the restriction oracle.
        var globalElements: [String: XSDTree] = [:]
        var groups: [String: XSDTree]
        /// Model-group definitions before a `redefine` overlay.
        var baseGroups: [String: XSDTree] = [:]
        /// Names of model groups redefined through `xs:redefine`.
        var redefinedGroups: Set<String> = []
        /// Named complex-type definition nodes, so a `complexContent` derivation can
        /// resolve and compose its base type's content model and attributes.
        var complexTypeNodes: [String: XSDTree] = [:]
        /// Complex-type definitions before a `redefine` overlay.
        var baseComplexTypeNodes: [String: XSDTree] = [:]
        /// Names of complex types redefined through `xs:redefine`.
        var redefinedComplexTypes: Set<String> = []
        /// The schema's target namespace, for resolving `##other`/`##targetNamespace`
        /// in wildcard constraints and qualifying global and qualified-form local
        /// declarations.
        var targetNamespace: String?
        /// Namespace prefix bindings declared on the schema root (`xmlns:p="..."`,
        /// the default namespace under the empty key), so an `xs:element ref="p:foo"`
        /// resolves to the namespace `p` is bound to rather than assuming the target
        /// namespace. An imported element reference is in the imported namespace.
        var namespaceBindings: [String: String] = [:]
        /// Whether `elementFormDefault="qualified"`: local element declarations are
        /// in the target namespace unless their own `form` overrides it.
        var elementFormQualified: Bool = false
        /// Whether `attributeFormDefault="qualified"`: local attribute declarations
        /// are in the target namespace unless their own `form` overrides it.
        var attributeFormQualified: Bool = false
        /// Each substitution-group head maps to its transitive member element
        /// names, so an `xs:element ref` to a head also admits its members.
        var substitutions: [String: [String]] = [:]
        /// Target namespace of each global element, keyed by local name.
        var elementNamespaces: [String: String?] = [:]
        /// Local names of element declarations declared `abstract="true"`, so a
        /// reference to an abstract head expands to its members but not the head.
        var abstractElements: Set<String> = []
        var visitingGroups: Set<String> = []
        /// Named complex types being resolved up the current `complexContent`
        /// derivation chain, a guard against a cyclic base reference.
        var visitingTypes: Set<String> = []
        /// Whether `include`/`import`/`redefine` targets were loaded through a
        /// `schemaLoader`, so cross-document rules may run over the merged component
        /// set instead of standing down.
        var compositionLoaded: Bool = false
        /// The schema's `blockDefault`, the `{disallowed substitutions}` a local or
        /// global element inherits when it states no `block` of its own.
        var blockDefault: String?
        /// The location of each container schema document.
        var containerLocations: [ObjectIdentifier: String?] = [:]
        /// Schema-location references (`include`/`import`/`redefine`) that the loader
        /// resolved to content which is not a well-formed schema document. Recorded
        /// during composition so a validation can report each (`src-resolve`); an
        /// unresolved location (the loader returned nothing) is not recorded.
        var failedSchemaReferences: [String] = []
        /// Target namespace imposed on an included schema with no `targetNamespace`
        /// (chameleon include), keyed by that included schema container.
        var chameleonTargetNamespaces: [ObjectIdentifier: String] = [:]
        /// The shared schema-validity finding collector. A reference type, so the
        /// value-type context's copies all report into the one place.
        let diagnostics = SchemaDiagnostics()
        /// Facet/pattern validity findings gathered during simple-type compilation,
        /// surfaced by the `simpleTypeFacetsAreValid` validation. A reference type so
        /// the value-type context's copies share the one sink.
        let facetFindingSink = CompileFindingSink()

        func visiting(_ group: String) -> XSDContext {
            var copy = self
            copy.visitingGroups.insert(group)
            return copy
        }

        func visitingType(_ type: String) -> XSDContext {
            var copy = self
            copy.visitingTypes.insert(type)
            return copy
        }

        /// Namespace and form defaults for components defined under `container`.
        func scoped(for container: XSDTree) -> XSDContext {
            var scoped = self
            let schema = XSDNode.schemaOwner(container)
            scoped.targetNamespace = XSDNode.attribute(schema, "targetNamespace")
            if scoped.targetNamespace?.isEmpty != false {
                scoped.targetNamespace = chameleonTargetNamespaces[ObjectIdentifier(schema)]
            }
            scoped.namespaceBindings = XSDNode.namespaceBindings(of: schema)
            scoped.elementFormQualified = XSDNode.attribute(schema, "elementFormDefault") == "qualified"
            scoped.attributeFormQualified = XSDNode.attribute(schema, "attributeFormDefault") == "qualified"
            return scoped
        }
    }
}
