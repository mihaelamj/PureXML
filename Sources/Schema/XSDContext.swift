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

        static func stripPrefix(_ qualified: String) -> String {
            qualified.split(separator: ":").last.map(String.init) ?? qualified
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
        ) -> [XSDTree] {
            var containers: [XSDTree] = []
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
                if let sub { containers += collectContainers(sub, loader, &visited) }
                if kind == "redefine" { containers.append(child) }
            }
            containers.append(schema)
            return containers
        }

        /// The transitive substitution-group membership across all definition
        /// containers: each head element maps to every element that may substitute
        /// for it, directly or through a chain of heads.
        static func substitutionMembers(_ containers: [XSDTree]) -> [String: [String]] {
            var direct: [String: [String]] = [:]
            for container in containers {
                for element in children(container, named: "element") {
                    guard let name = attribute(element, "name"), let head = attribute(element, "substitutionGroup") else {
                        continue
                    }
                    direct[stripPrefix(head), default: []].append(name)
                }
            }
            var closure: [String: [String]] = [:]
            for head in direct.keys {
                var members: [String] = []
                var stack = direct[head] ?? []
                var seen: Set<String> = []
                while let member = stack.popLast() {
                    guard seen.insert(member).inserted else { continue }
                    members.append(member)
                    stack += direct[member] ?? []
                }
                closure[head] = members
            }
            return closure
        }
    }

    /// The result of compiling a schema document: its global element
    /// declarations, its named-type table, and the identity constraints declared
    /// on each element name.
    struct XSDCompiled {
        var elements: [String: ElementType]
        var types: [String: ElementType]
        var constraints: [String: [IdentityConstraint]]
        /// Local names of elements declared `nillable="true"`.
        var nillableElements: Set<String> = []
        /// The `default`/`fixed` value constraint declared on each element name.
        var elementConstraints: [String: ValueConstraint] = [:]
        /// Local names of complex types declared `abstract="true"`: an element of
        /// such a type must supply an `xsi:type` naming a concrete derived type.
        var abstractTypes: Set<String> = []
        /// Local names of element declarations declared `abstract="true"`: they may
        /// not appear in an instance directly, only through a substitution member.
        var abstractElements: Set<String> = []
        /// Derivation methods the named type forbids when used through `xsi:type`.
        var typeBlock: [String: Set<DerivationMethod>] = [:]
        /// Derivation methods each element declaration forbids through `xsi:type`.
        var elementBlock: [String: Set<DerivationMethod>] = [:]
        /// Each named complex type's base type and derivation method, the backbone
        /// the `block` check walks from an `xsi:type` to its declared type.
        var typeDerivation: [String: TypeDerivation] = [:]
        /// Derivation methods each named type declares `final`, for the
        /// schema-consistency rules.
        var typeFinal: [String: Set<DerivationMethod>] = [:]
        /// The schema's target namespace, so the root element's namespace can be
        /// checked against it.
        var targetNamespace: String?
    }

    /// The parsing context: the named simple types resolved so far, plus the
    /// definition nodes for named attribute groups and model groups (so their
    /// refs can be expanded), and a guard against cyclic group references.
    struct XSDContext {
        var simpleTypes: [String: SimpleType]
        var attributeGroups: [String: XSDTree]
        var groups: [String: XSDTree]
        /// Named complex-type definition nodes, so a `complexContent` derivation can
        /// resolve and compose its base type's content model and attributes.
        var complexTypeNodes: [String: XSDTree] = [:]
        /// The schema's target namespace, for resolving `##other`/`##targetNamespace`
        /// in wildcard constraints and qualifying global and qualified-form local
        /// declarations.
        var targetNamespace: String?
        /// Whether `elementFormDefault="qualified"`: local element declarations are
        /// in the target namespace unless their own `form` overrides it.
        var elementFormQualified: Bool = false
        /// Whether `attributeFormDefault="qualified"`: local attribute declarations
        /// are in the target namespace unless their own `form` overrides it.
        var attributeFormQualified: Bool = false
        /// Each substitution-group head maps to its transitive member element
        /// names, so an `xs:element ref` to a head also admits its members.
        var substitutions: [String: [String]] = [:]
        /// Local names of element declarations declared `abstract="true"`, so a
        /// reference to an abstract head expands to its members but not the head.
        var abstractElements: Set<String> = []
        var visitingGroups: Set<String> = []
        /// Named complex types being resolved up the current `complexContent`
        /// derivation chain, a guard against a cyclic base reference.
        var visitingTypes: Set<String> = []

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
    }
}
