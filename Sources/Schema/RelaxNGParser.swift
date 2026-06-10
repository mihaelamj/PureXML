private typealias Tree = RNGTree

/// Compiles a RELAX NG XML-syntax document into the pattern algebra, resolving
/// `include` and `externalRef` through a loader. Holds the accumulating `define`
/// table so external grammars merge into it. File-scope and private.
final class RNGCompiler {
    typealias Pattern = PureXML.Schema.Pattern
    typealias NameClass = PureXML.Schema.NameClass
    typealias Compositor = PureXML.Schema.Compositor

    private(set) var defines: [String: Pattern] = [:]
    /// The combine method established for each define name (4.17): defines
    /// sharing a name agree on one method, and the single define that omits
    /// `combine` still merges by it.
    private var defineCombine: [String: String] = [:]
    /// How many defines of each name omitted `combine` (at most one may).
    private var combinelessDefines: [String: Int] = [:]
    /// Every ref/parentRef target, checked against the defines at the end.
    private var referenced: Set<String> = []
    /// Schema-correctness problems discovered during compilation.
    var violations: [String] = []
    let loader: (String) -> String?
    var visited: Set<String> = []
    /// The URI of the document currently being compiled (nil for the top
    /// level): hrefs inside a loaded document resolve against it.
    var documentBase: String?
    /// The `ns` value carried across a document boundary: an externalRef's
    /// in-scope ns applies to the loaded pattern when it has none of its own
    /// (simplification 4.6); the tree-ancestor walk cannot cross documents.
    var fallbackNamespace = ""
    /// The start pattern contributed by an `include`d grammar (4.7), used when
    /// the including grammar declares no start of its own.
    var includedStart: Pattern?
    /// Each `grammar` element opens its own define scope; names are mangled
    /// with the scope identifier so nested grammars do not collide and
    /// `parentRef` reaches the enclosing grammar's scope.
    private var scopeStack: [Int] = []
    private var nextScope = 0

    private func mangled(_ name: String) -> String {
        "\(scopeStack.last ?? 0)\u{1}\(name)"
    }

    /// Builds a ref, recording the target for the resolution check; a
    /// parentRef outside any nested grammar is a schema error.
    private func reference(_ name: String, parent: Bool) -> Pattern {
        if parent, scopeStack.count < 2 {
            violations.append("parentRef '\(name)' has no enclosing grammar")
            return .notAllowed
        }
        let target = parent ? parentMangled(name) : mangled(name)
        referenced.insert(target)
        return .ref(target)
    }

    private func parentMangled(_ name: String) -> String {
        let parent = scopeStack.count >= 2 ? scopeStack[scopeStack.count - 2] : (scopeStack.last ?? 0)
        return "\(parent)\u{1}\(name)"
    }

    /// The ns in scope at a schema node: its own/ancestor `ns` attribute, or
    /// the namespace inherited across the document boundary.
    func effectiveNS(_ node: Tree) -> String {
        RNGNode.inheritedNS(node) ?? fallbackNamespace
    }

    init(loader: @escaping (String) -> String?) {
        self.loader = loader
    }

    /// Refs whose targets no define supplies, as schema errors.
    func unresolvedReferences() -> [String] {
        referenced.subtracting(defines.keys).sorted().map { target in
            let name = target.split(separator: "\u{1}").last.map(String.init) ?? target
            return "ref '\(name)' has no matching define"
        }
    }

    func topLevel(_ node: Tree) -> Pattern {
        RNGNode.localName(node) == "grammar" ? grammar(node) : pattern(node)
    }

    private func grammar(_ node: Tree) -> Pattern {
        scopeStack.append(nextScope)
        nextScope += 1
        let outerIncludedStart = includedStart
        includedStart = nil
        defer {
            scopeStack.removeLast()
            includedStart = outerIncludedStart
        }
        for include in RNGNode.components(node, named: "include") {
            mergeInclude(include)
        }
        for define in RNGNode.components(node, named: "define") {
            addDefine(define)
        }
        let starts = RNGNode.components(node, named: "start")
        guard let first = starts.first else {
            if includedStart == nil {
                violations.append("grammar has no start")
            }
            return includedStart ?? .notAllowed
        }
        // Multiple starts combine like defines (4.17): the named method wins,
        // and the single start that omits `combine` still merges by it.
        var method: String?
        for start in starts {
            if let named = RNGNode.attribute(start, "combine") { method = named }
        }
        var result = combined(RNGNode.elementChildren(first), .sequence)
        for start in starts.dropFirst() {
            let next = combined(RNGNode.elementChildren(start), .sequence)
            switch method {
            case "choice": result = .choice(result, next)
            case "interleave": result = .interleave(result, next)
            default: result = next
            }
        }
        return result
    }

    /// Adds a `define`, honoring `combine`: a second definition of the same name
    /// with `combine="choice"`/`"interleave"` merges with the existing one rather
    /// than replacing it (a plain redefinition still replaces).
    func addDefine(_ define: Tree) {
        guard let rawName = RNGNode.attribute(define, "name") else { return }
        let name = mangled(rawName)
        let pattern = combined(RNGNode.elementChildren(define), .sequence)
        if let method = RNGNode.attribute(define, "combine") {
            if let established = defineCombine[name], established != method {
                violations.append("define '\(rawName)' uses conflicting combine methods (4.17)")
            }
            defineCombine[name] = method
        } else {
            combinelessDefines[name, default: 0] += 1
            if combinelessDefines[name] == 2 {
                violations.append("more than one define of '\(rawName)' omits combine (4.17)")
            }
        }
        guard let existing = defines[name] else {
            defines[name] = pattern
            return
        }
        switch defineCombine[name] {
        case "choice": defines[name] = .choice(existing, pattern)
        case "interleave": defines[name] = .interleave(existing, pattern)
        default: defines[name] = pattern
        }
    }

    // MARK: Patterns

    func pattern(_ node: Tree) -> Pattern {
        leafPattern(node) ?? compositePattern(node)
    }

    private func leafPattern(_ node: Tree) -> Pattern? {
        switch RNGNode.localName(node) {
        case "empty": .empty
        case "notAllowed": .notAllowed
        case "text": .text
        case "data": dataPattern(node)
        case "value": valuePattern(node)
        case "element": element(node)
        case "attribute": attribute(node)
        default: referencePattern(node)
        }
    }

    /// The reference-shaped leaves: named refs (scope-mangled), parent refs,
    /// nested grammars, and external references.
    private func referencePattern(_ node: Tree) -> Pattern? {
        switch RNGNode.localName(node) {
        case "ref": reference(RNGNode.attribute(node, "name") ?? "", parent: false)
        case "parentRef": reference(RNGNode.attribute(node, "name") ?? "", parent: true)
        case "grammar": grammar(node)
        case "externalRef": externalRef(node)
        default: nil
        }
    }

    /// The URI of the W3C XML Schema datatype library; the only non-default
    /// library RELAX NG processors are required to support.
    private static let xsdDatatypeLibrary = "http://www.w3.org/2001/XMLSchema-datatypes"

    /// Builds a `<data type=>` pattern: its base built-in plus the facets its
    /// `<param name= >value</param>` children constrain it with (the same facet
    /// set the XSD datatypes use). A `type` that the in-scope `datatypeLibrary`
    /// does not define is an unknown datatype, so the pattern matches nothing.
    private func dataPattern(_ node: Tree) -> Pattern {
        let typeName = RNGNode.strip(RNGNode.attribute(node, "type") ?? "string")
        guard let base = resolvedBuiltin(typeName, library: datatypeLibrary(of: node)) else {
            violations.append("datatype '\(typeName)' is not defined by the datatype library in scope")
            return .notAllowed
        }
        var facets = PureXML.Schema.Facets()
        for param in RNGNode.children(node, named: "param") {
            if let name = RNGNode.attribute(param, "name") {
                PureXML.Schema.RelaxNGFacets.apply(name, RNGNode.text(param), into: &facets)
            }
        }
        if datatypeLibrary(of: node) == "", !RNGNode.children(node, named: "param").isEmpty {
            violations.append("the built-in datatype library defines no params for '\(typeName)'")
        }
        let type = PureXML.Schema.SimpleType(base: base, facets: facets)
        // 4.12: an except child excludes its (implicitly choice-combined)
        // patterns from the data type's lexical space.
        if let except = RNGNode.children(node, named: "except").first {
            return .dataExcept(type, combined(RNGNode.elementChildren(except), .choice))
        }
        return .data(type)
    }

    /// Builds a `<value>` pattern carrying its datatype, so the value compares in
    /// that type's value space. An untyped `<value>` uses the built-in `token`
    /// type; an explicit `type` the in-scope `datatypeLibrary` does not define is
    /// an unknown datatype, so the value matches nothing.
    private func valuePattern(_ node: Tree) -> Pattern {
        guard let type = valueType(node) else {
            violations.append("datatype '\(RNGNode.attribute(node, "type") ?? "")' is not defined by the datatype library in scope")
            return .notAllowed
        }
        if type.base == .qName {
            // The QName value space: resolve the literal's prefix against the
            // schema's xmlns scope; an unprefixed literal takes the in-scope
            // ns attribute (6.2.9).
            let raw = RNGNode.text(node)
            if let qualified = RNGNode.resolveQName(raw, at: node) {
                return .valueQName(namespace: qualified.namespace, localName: qualified.localName)
            }
            return .valueQName(namespace: effectiveNS(node), localName: raw)
        }
        return .value(type, RNGNode.rawText(node))
    }

    /// The datatype of a `<value>`: `token` when untyped, the library-resolved
    /// built-in when typed, or nil when the declared type is unknown.
    private func valueType(_ node: Tree) -> PureXML.Schema.SimpleType? {
        guard let declared = RNGNode.attribute(node, "type") else {
            return PureXML.Schema.SimpleType(base: .token)
        }
        guard let base = resolvedBuiltin(RNGNode.strip(declared), library: datatypeLibrary(of: node)) else {
            return nil
        }
        return PureXML.Schema.SimpleType(base: base)
    }

    /// Resolves a datatype name within a library. The default (empty) library
    /// defines only `string` and `token`; the XSD library defines every built-in;
    /// any other library is unsupported, so its names are unknown.
    private func resolvedBuiltin(_ typeName: String, library: String) -> PureXML.Schema.BuiltinType? {
        switch library {
        case "": typeName == "string" || typeName == "token" ? PureXML.Schema.BuiltinType(rawValue: typeName) : nil
        case Self.xsdDatatypeLibrary: PureXML.Schema.BuiltinType(rawValue: typeName)
        default: nil
        }
    }

    /// The `datatypeLibrary` in scope at `node`: the nearest value on the node or
    /// an ancestor, defaulting to the empty (RELAX NG built-in) library.
    private func datatypeLibrary(of node: Tree) -> String {
        var current: Tree? = node
        while let candidate = current {
            if let library = RNGNode.attribute(candidate, "datatypeLibrary") { return library }
            current = candidate.parent
        }
        return ""
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
            // The schema document must itself match the RELAX NG grammar.
            if let problem = RelaxNGGrammarCheck.violation(top) {
                throw PureXML.Schema.SchemaError.invalidRelaxNG(reason: problem)
            }
            let compiler = RNGCompiler(loader: loader)
            let start = compiler.topLevel(top)
            let unresolved = compiler.unresolvedReferences()
            if let problem = compiler.violations.first ?? unresolved.first {
                throw PureXML.Schema.SchemaError.invalidRelaxNG(reason: problem)
            }
            if let problem = RelaxNGRestrictions.violation(start: start, defines: compiler.defines) {
                throw PureXML.Schema.SchemaError.invalidRelaxNG(reason: problem)
            }
            return (start, compiler.defines)
        }
    }
}
