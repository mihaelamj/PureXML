private typealias Tree = PureXML.Model.TreeNode

/// Tree helpers for the RELAX NG parser. File-scope and private.
private enum RNGNode {
    static func localName(_ node: Tree) -> String? {
        node.name?.localName
    }

    static func attribute(_ node: Tree, _ name: String) -> String? {
        node.attributes.first { $0.name.localName == name }?.value
    }

    static func elementChildren(_ node: Tree) -> [Tree] {
        node.children.filter { $0.kind == .element }
    }

    static func children(_ node: Tree, named name: String) -> [Tree] {
        elementChildren(node).filter { localName($0) == name }
    }

    static func text(_ node: Tree) -> String {
        node.stringValue.trimmingXMLWhitespace()
    }

    static func strip(_ qualified: String) -> String {
        qualified.split(separator: ":").last.map(String.init) ?? qualified
    }
}

/// Compiles a RELAX NG XML-syntax document into the pattern algebra, resolving
/// `include` and `externalRef` through a loader. Holds the accumulating `define`
/// table so external grammars merge into it. File-scope and private.
private final class RNGCompiler {
    typealias Pattern = PureXML.Schema.Pattern
    typealias NameClass = PureXML.Schema.NameClass
    typealias Compositor = PureXML.Schema.Compositor

    private(set) var defines: [String: Pattern] = [:]
    private let loader: (String) -> String?
    private var visited: Set<String> = []

    init(loader: @escaping (String) -> String?) {
        self.loader = loader
    }

    func topLevel(_ node: Tree) -> Pattern {
        RNGNode.localName(node) == "grammar" ? grammar(node) : pattern(node)
    }

    private func grammar(_ node: Tree) -> Pattern {
        for include in RNGNode.children(node, named: "include") {
            mergeInclude(include)
        }
        for define in RNGNode.children(node, named: "define") {
            addDefine(define)
        }
        let start = RNGNode.children(node, named: "start").first
        return start.map { combined(RNGNode.elementChildren($0), .sequence) } ?? .notAllowed
    }

    /// Adds a `define`, honoring `combine`: a second definition of the same name
    /// with `combine="choice"`/`"interleave"` merges with the existing one rather
    /// than replacing it (a plain redefinition still replaces).
    private func addDefine(_ define: Tree) {
        guard let name = RNGNode.attribute(define, "name") else { return }
        let pattern = combined(RNGNode.elementChildren(define), .sequence)
        guard let existing = defines[name] else {
            defines[name] = pattern
            return
        }
        switch RNGNode.attribute(define, "combine") {
        case "choice": defines[name] = .choice(existing, pattern)
        case "interleave": defines[name] = .interleave(existing, pattern)
        default: defines[name] = pattern
        }
    }

    /// Merges an `include`d grammar: its `define`s first, then the `include`'s own
    /// nested `define`s, which override or (with `combine`) merge with them.
    private func mergeInclude(_ node: Tree) {
        guard let href = RNGNode.attribute(node, "href"), !visited.contains(href),
              let text = loader(href), let root = try? PureXML.parseTree(text),
              let grammar = RNGNode.elementChildren(root).first
        else {
            return
        }
        visited.insert(href)
        for define in RNGNode.children(grammar, named: "define") {
            addDefine(define)
        }
        for define in RNGNode.children(node, named: "define") {
            addDefine(define)
        }
    }

    // MARK: Patterns

    private func pattern(_ node: Tree) -> Pattern {
        leafPattern(node) ?? compositePattern(node)
    }

    private func leafPattern(_ node: Tree) -> Pattern? {
        switch RNGNode.localName(node) {
        case "empty": .empty
        case "notAllowed": .notAllowed
        case "text": .text
        case "data": .data(dataType(node))
        case "value": .value(RNGNode.text(node))
        case "ref": .ref(RNGNode.attribute(node, "name") ?? "")
        case "externalRef": externalRef(node)
        case "element": element(node)
        case "attribute": attribute(node)
        default: nil
        }
    }

    /// Builds the datatype of a `<data type=>` pattern: its base built-in plus the
    /// facets its `<param name= >value</param>` children constrain it with (the
    /// same facet set the XSD datatypes use).
    private func dataType(_ node: Tree) -> PureXML.Schema.SimpleType {
        let base = PureXML.Schema.BuiltinType(rawValue: RNGNode.strip(RNGNode.attribute(node, "type") ?? "string")) ?? .string
        var facets = PureXML.Schema.Facets()
        for param in RNGNode.children(node, named: "param") {
            if let name = RNGNode.attribute(param, "name") {
                PureXML.Schema.RelaxNGFacets.apply(name, RNGNode.text(param), into: &facets)
            }
        }
        return PureXML.Schema.SimpleType(base: base, facets: facets)
    }

    /// Resolves an `externalRef` to the referenced schema's pattern, merging any
    /// grammar `define`s it carries into this compiler's table.
    private func externalRef(_ node: Tree) -> Pattern {
        guard let href = RNGNode.attribute(node, "href"), !visited.contains(href),
              let text = loader(href), let root = try? PureXML.parseTree(text),
              let top = RNGNode.elementChildren(root).first
        else {
            return .notAllowed
        }
        visited.insert(href)
        return topLevel(top)
    }

    private func compositePattern(_ node: Tree) -> Pattern {
        switch RNGNode.localName(node) {
        case "group": combined(RNGNode.elementChildren(node), .sequence)
        case "choice": combined(RNGNode.elementChildren(node), .choice)
        case "interleave": combined(RNGNode.elementChildren(node), .all)
        case "optional": .choice(group(node), .empty)
        case "zeroOrMore": .choice(.oneOrMore(group(node)), .empty)
        case "oneOrMore": .oneOrMore(group(node))
        case "mixed": .interleave(group(node), .text)
        case "list": .list(group(node))
        default: .notAllowed
        }
    }

    private func group(_ node: Tree) -> Pattern {
        combined(RNGNode.elementChildren(node), .sequence)
    }

    private func element(_ node: Tree) -> Pattern {
        let (nameClass, contentNodes) = nameClassAndContent(node)
        return .element(nameClass, combined(contentNodes, .sequence))
    }

    private func attribute(_ node: Tree) -> Pattern {
        let (nameClass, contentNodes) = nameClassAndContent(node)
        let content = contentNodes.isEmpty ? Pattern.text : combined(contentNodes, .sequence)
        return .attribute(nameClass, content)
    }

    private func nameClassAndContent(_ node: Tree) -> (NameClass, [Tree]) {
        let children = RNGNode.elementChildren(node)
        if let name = RNGNode.attribute(node, "name") {
            let namespace = RNGNode.attribute(node, "ns") ?? ""
            return (.name(namespace: namespace, localName: name), children)
        }
        guard let first = children.first else { return (.anyName, []) }
        return (nameClass(first), Array(children.dropFirst()))
    }

    // MARK: Combinators and name classes

    private func combined(_ nodes: [Tree], _ compositor: Compositor) -> Pattern {
        let patterns = nodes.map(pattern)
        let identity: Pattern = compositor == .choice ? .notAllowed : .empty
        guard let first = patterns.first else { return identity }
        return patterns.dropFirst().reduce(first) { combine($0, $1, compositor) }
    }

    private func combine(_ lhs: Pattern, _ rhs: Pattern, _ compositor: Compositor) -> Pattern {
        switch compositor {
        case .sequence: .group(lhs, rhs)
        case .choice: .choice(lhs, rhs)
        case .all: .interleave(lhs, rhs)
        }
    }

    private func nameClass(_ node: Tree) -> NameClass {
        switch RNGNode.localName(node) {
        case "name":
            .name(namespace: RNGNode.attribute(node, "ns") ?? "", localName: RNGNode.text(node))
        case "anyName":
            anyName(node)
        case "nsName":
            .nsName(RNGNode.attribute(node, "ns") ?? "")
        case "choice":
            nameClassChoice(RNGNode.elementChildren(node))
        default:
            .anyName
        }
    }

    private func anyName(_ node: Tree) -> NameClass {
        guard let except = RNGNode.children(node, named: "except").first,
              let inner = RNGNode.elementChildren(except).first
        else {
            return .anyName
        }
        return .anyNameExcept(nameClass(inner))
    }

    private func nameClassChoice(_ nodes: [Tree]) -> NameClass {
        let classes = nodes.map(nameClass)
        guard let first = classes.first else { return .anyName }
        return classes.dropFirst().reduce(first) { .choice($0, $1) }
    }
}

extension PureXML.Schema {
    /// Parses a RELAX NG schema in the XML syntax into a grammar: a start pattern
    /// and the named `define` patterns it refers to. The vocabulary is matched by
    /// local name. Supports `element`, `attribute`, `text`, `empty`, `notAllowed`,
    /// `group`, `choice`, `interleave`, `optional`, `zeroOrMore`, `oneOrMore`,
    /// `mixed`, `list`, `ref`, `data`, `value`, the name classes, and `include`
    /// and `externalRef` resolved through `loader`.
    enum RelaxNGParser {
        static func parse(
            _ rng: String,
            loader: @escaping (String) -> String? = { _ in nil },
        ) throws -> (start: Pattern, defines: [String: Pattern]) {
            let root = try PureXML.parseTree(rng)
            guard let top = RNGNode.elementChildren(root).first else {
                throw PureXML.Schema.SchemaError.notASchema
            }
            let compiler = RNGCompiler(loader: loader)
            let start = compiler.topLevel(top)
            return (start, compiler.defines)
        }
    }
}
