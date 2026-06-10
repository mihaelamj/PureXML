/// The include and externalRef resolution of the RELAX NG compiler, split
/// from the compiler body for the length caps: transitive merging with 4.7
/// overrides, per-document bases, cross-document ns, and cycle detection.
extension RNGCompiler {
    /// Merges an `include`d grammar: its `define`s first, then the `include`'s own
    /// nested `define`s, which override or (with `combine`) merge with them.
    func mergeInclude(_ node: Tree) {
        guard let href = RNGNode.resolvedHref(node, documentBase: documentBase) else { return }
        guard !visited.contains(href) else {
            violations.append("include '\(href)' includes itself")
            return
        }
        guard let grammar = loadedGrammar(href) else { return }
        visited.insert(href)
        defer { visited.remove(href) }
        mergeLoadedGrammar(grammar, from: node, href: href)
        if let override = RNGNode.children(node, named: "start").first {
            includedStart = combined(RNGNode.elementChildren(override), .sequence)
        }
        for define in RNGNode.children(node, named: "define") {
            addDefine(define)
        }
    }

    /// Merges the loaded grammar's components under its own base and
    /// namespace scope: transitive includes first, then its defines (minus
    /// the include's overrides) and its start.
    private func mergeLoadedGrammar(_ grammar: Tree, from node: Tree, href: String) {
        let outerBase = documentBase
        let outerNamespace = fallbackNamespace
        documentBase = href
        if RNGNode.inheritedNS(grammar) == nil {
            fallbackNamespace = effectiveNS(node)
        }
        defer {
            documentBase = outerBase
            fallbackNamespace = outerNamespace
        }
        // The included grammar's own includes merge first (4.7 is transitive).
        for nested in RNGNode.components(grammar, named: "include") {
            mergeInclude(nested)
        }
        let overrides = includeOverrides(node, grammar: grammar)
        for define in RNGNode.components(grammar, named: "define") {
            guard let name = RNGNode.attribute(define, "name"), !overrides.contains(name) else { continue }
            addDefine(define)
        }
        if includedStart == nil, let start = RNGNode.components(grammar, named: "start").first {
            includedStart = combined(RNGNode.elementChildren(start), .sequence)
        }
    }

    /// A define carried by the include element REPLACES the included
    /// grammar's define of the same name (4.7 override); an override with
    /// nothing to override is a schema error.
    private func includeOverrides(_ node: Tree, grammar: Tree) -> Set<String> {
        let overrides = Set(RNGNode.children(node, named: "define").compactMap { RNGNode.attribute($0, "name") })
        let provided = Set(RNGNode.components(grammar, named: "define").compactMap { RNGNode.attribute($0, "name") })
        for name in overrides.sorted() where !provided.contains(name) {
            violations.append("include overrides define '\(name)', which the included grammar does not define")
        }
        let overridesStart = RNGNode.children(node, named: "start").first != nil
        if overridesStart, RNGNode.components(grammar, named: "start").first == nil {
            violations.append("include overrides the start, which the included grammar does not define")
        }
        return overrides
    }

    /// Loads and validates an include's target, which must be a grammatical
    /// RELAX NG grammar element.
    private func loadedGrammar(_ href: String) -> Tree? {
        guard let text = loader(href), let root = try? PureXML.parseTree(text),
              let grammar = RNGNode.elementChildren(root).first
        else {
            return nil
        }
        if RNGNode.localName(grammar) != "grammar" {
            violations.append("include '\(href)' must reference a grammar")
            return nil
        }
        if let problem = RelaxNGGrammarCheck.violation(grammar) {
            violations.append("included schema '\(href)': \(problem)")
            return nil
        }
        return grammar
    }

    func externalRef(_ node: Tree) -> Pattern {
        guard let href = RNGNode.resolvedHref(node, documentBase: documentBase) else { return .notAllowed }
        guard !visited.contains(href) else {
            violations.append("externalRef '\(href)' references itself")
            return .notAllowed
        }
        guard let text = loader(href), let root = try? PureXML.parseTree(text),
              let top = RNGNode.elementChildren(root).first
        else {
            return .notAllowed
        }
        if let problem = RelaxNGGrammarCheck.violation(top) {
            violations.append("referenced schema '\(href)': \(problem)")
            return .notAllowed
        }
        visited.insert(href)
        defer { visited.remove(href) }
        let outerBase = documentBase
        let outerNamespace = fallbackNamespace
        documentBase = href
        if RNGNode.inheritedNS(top) == nil {
            fallbackNamespace = effectiveNS(node)
        }
        defer {
            documentBase = outerBase
            fallbackNamespace = outerNamespace
        }
        return topLevel(top)
    }
}
