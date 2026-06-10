/// The name-class side of the RELAX NG compiler (4.9-4.10: ns inheritance and
/// QName resolution), split from the compiler body to keep it under the
/// length caps.
extension RNGCompiler {
    typealias Tree = RNGTree

    func nameClassAndContent(_ node: Tree) -> (NameClass, [Tree]) {
        let children = RNGNode.elementChildren(node)
        if let name = RNGNode.attribute(node, "name") {
            if let qualified = RNGNode.resolveQName(name, at: node) {
                return (.name(namespace: qualified.namespace, localName: qualified.localName), children)
            }
            // The `name=` shorthand on an attribute does not inherit ns: an
            // unprefixed attribute name has no namespace unless the attribute
            // element itself carries ns (4.9). Elements inherit normally.
            let isAttribute = RNGNode.localName(node) == "attribute"
            let namespace = isAttribute
                ? (node.attributes.first { $0.name.prefix == nil && $0.name.localName == "ns" }?.value ?? "")
                : effectiveNS(node)
            return (.name(namespace: namespace, localName: name), children)
        }
        guard let first = children.first else { return (.anyName, []) }
        return (nameClass(first), Array(children.dropFirst()))
    }

    // MARK: Combinators and name classes

    func combined(_ nodes: [Tree], _ compositor: Compositor) -> Pattern {
        let patterns = nodes.map(pattern)
        let identity: Pattern = compositor == .choice ? .notAllowed : .empty
        guard let first = patterns.first else { return identity }
        return patterns.dropFirst().reduce(first) { combine($0, $1, compositor) }
    }

    func combine(_ lhs: Pattern, _ rhs: Pattern, _ compositor: Compositor) -> Pattern {
        switch compositor {
        case .sequence: .group(lhs, rhs)
        case .choice: .choice(lhs, rhs)
        case .all: .interleave(lhs, rhs)
        }
    }

    func nameClass(_ node: Tree) -> NameClass {
        switch RNGNode.localName(node) {
        case "name":
            nameElementClass(node)
        case "anyName":
            anyName(node)
        case "nsName":
            nsName(node)
        case "choice":
            nameClassChoice(RNGNode.elementChildren(node))
        default:
            .anyName
        }
    }

    func anyName(_ node: Tree) -> NameClass {
        guard let except = exceptClass(node) else { return .anyName }
        return .anyNameExcept(except)
    }

    /// A `<name>` element: its text may be a QName resolved against in-scope
    /// xmlns declarations (4.10); otherwise the inherited ns applies (4.9).
    func nameElementClass(_ node: Tree) -> NameClass {
        let raw = RNGNode.text(node)
        if let qualified = RNGNode.resolveQName(raw, at: node) {
            return .name(namespace: qualified.namespace, localName: qualified.localName)
        }
        return .name(namespace: effectiveNS(node), localName: raw)
    }

    func nsName(_ node: Tree) -> NameClass {
        let namespace = effectiveNS(node)
        guard let except = exceptClass(node) else { return .nsName(namespace) }
        return .nsNameExcept(namespace: namespace, except: except)
    }

    /// The name class of a `<name-class>`'s `<except>` child, treating multiple
    /// children as an implicit choice (`anyName`/`nsName` minus the union).
    func exceptClass(_ node: Tree) -> NameClass? {
        guard let except = RNGNode.children(node, named: "except").first else { return nil }
        let children = RNGNode.elementChildren(except)
        return children.isEmpty ? nil : nameClassChoice(children)
    }

    func nameClassChoice(_ nodes: [Tree]) -> NameClass {
        let classes = nodes.map(nameClass)
        guard let first = classes.first else { return .anyName }
        return classes.dropFirst().reduce(first) { .choice($0, $1) }
    }
}
