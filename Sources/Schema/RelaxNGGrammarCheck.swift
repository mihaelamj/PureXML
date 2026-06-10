/// Validates a RELAX NG schema document against the RELAX NG grammar itself
/// (spec section 3) and the name-class/except restrictions of section 4.16,
/// before any pattern interpretation: unknown or misplaced elements, missing
/// or illegal attributes, wrong child arity, stray text, and prohibited
/// except contents are all schema errors. Foreign-namespace elements and
/// qualified attributes are annotations and ignored throughout.
enum RelaxNGGrammarCheck {
    /// The context an element is interpreted in.
    enum Context: Equatable {
        case pattern
        case nameClass
        case grammarContent
        case includeContent
        case dataExcept
        case exceptInAnyName
        case exceptInNsName
    }

    /// The first violation in the schema, or nil when it is grammatical.
    static func violation(_ top: RNGTree) -> String? {
        check(top, in: .pattern)
    }

    static func check(_ node: RNGTree, in context: Context) -> String? {
        guard let name = RNGNode.localName(node) else { return nil }
        if let problem = attributeProblem(node, name: name) { return problem }
        if let problem = textProblem(node, name: name) { return problem }
        switch context {
        case .pattern: return checkPattern(node, name: name)
        case .nameClass: return checkNameClass(node, name: name)
        case .grammarContent: return checkGrammarComponent(node, name: name, allowIncludes: true)
        case .includeContent: return checkGrammarComponent(node, name: name, allowIncludes: false)
        case .dataExcept: return checkDataExceptMember(node, name: name)
        case .exceptInAnyName, .exceptInNsName: return checkExceptMember(node, name: name, in: context)
        }
    }

    /// A member of a name-class except: the 4.16 prohibitions, propagated
    /// through choice wrappers.
    private static func checkExceptMember(_ node: RNGTree, name: String, in context: Context) -> String? {
        if context == .exceptInAnyName, name == "anyName" {
            return "anyName is not allowed inside an anyName except (4.16)"
        }
        if context == .exceptInNsName, name == "anyName" || name == "nsName" {
            return "\(name) is not allowed inside an nsName except (4.16)"
        }
        if name == "choice" {
            let members = RNGNode.elementChildren(node)
            guard !members.isEmpty else { return "<choice> needs at least one name class" }
            return firstViolation(members, in: context)
        }
        return checkNameClass(node, name: name)
    }

    // MARK: Patterns

    private static func checkPattern(_ node: RNGTree, name: String) -> String? {
        let children = RNGNode.elementChildren(node)
        switch name {
        case "element", "attribute":
            return checkNamed(node, name: name, children: children)
        case "group", "interleave", "choice", "optional", "zeroOrMore", "oneOrMore", "mixed", "list":
            guard !children.isEmpty else { return "<\(name)> needs at least one pattern" }
            return firstViolation(children, in: .pattern)
        case "data":
            return checkData(node, children: children)
        case "grammar":
            return firstViolation(children, in: .grammarContent)
        default:
            return checkLeafPattern(node, name: name, children: children)
        }
    }

    /// The childless leaves: refs, the empty family, value, externalRef.
    private static func checkLeafPattern(_ node: RNGTree, name: String, children: [RNGTree]) -> String? {
        switch name {
        case "ref", "parentRef":
            guard hasNCName(node, "name") else { return "<\(name)> needs an NCName name attribute" }
            return children.isEmpty ? nil : "<\(name)> has no content"
        case "empty", "text", "notAllowed":
            return children.isEmpty ? nil : "<\(name)> has no content"
        case "value":
            return children.isEmpty ? nil : "<value> holds text only"
        case "externalRef":
            guard RNGNode.attribute(node, "href") != nil else { return "<externalRef> needs an href attribute" }
            return children.isEmpty ? nil : "<externalRef> has no content"
        default:
            return "<\(name)> is not a RELAX NG pattern"
        }
    }

    /// `element`/`attribute`: a name attribute or a leading name class, then
    /// content (at least one pattern for element, at most one for attribute).
    private static func checkNamed(_ node: RNGTree, name: String, children: [RNGTree]) -> String? {
        var content = children[...]
        if let qualified = RNGNode.attribute(node, "name") {
            guard isQName(qualified) else {
                return "<\(name)> has a malformed name attribute"
            }
            if qualified.contains(":"), RNGNode.resolveQName(qualified, at: node) == nil {
                return "the prefix of '\(qualified)' is not declared"
            }
        } else {
            guard let nameClass = content.first else { return "<\(name)> needs a name class" }
            if let problem = check(nameClass, in: .nameClass) { return problem }
            content = content.dropFirst()
        }
        if name == "element", content.isEmpty {
            return "<element> needs a content pattern"
        }
        if name == "attribute", content.count > 1 {
            return "<attribute> takes at most one pattern"
        }
        if name == "attribute", let problem = xmlnsAttributeProblem(node) {
            return problem
        }
        return firstViolation(Array(content), in: .pattern)
    }

    /// An attribute must not be named `xmlns` (with no namespace) nor live in
    /// the xmlns namespace name (4.16).
    private static func xmlnsAttributeProblem(_ node: RNGTree) -> String? {
        if let name = RNGNode.attribute(node, "name") {
            let namespaceName = node.attributes.first { $0.name.prefix == nil && $0.name.localName == "ns" }?.value ?? ""
            return xmlnsMentionProblem(localName: name, namespaceName: namespaceName)
        }
        var stack = RNGNode.elementChildren(node).prefix(1).map(\.self)
        while let nameClass = stack.popLast() {
            let local = RNGNode.localName(nameClass)
            if local == "name" || local == "nsName" {
                let namespaceName = RNGNode.attribute(nameClass, "ns") ?? RNGNode.inheritedNS(nameClass) ?? ""
                let mentioned = local == "name" ? RNGNode.text(nameClass) : nil
                if let problem = xmlnsMentionProblem(localName: mentioned, namespaceName: namespaceName) {
                    return problem
                }
            }
            if local != "name" {
                stack.append(contentsOf: RNGNode.elementChildren(nameClass))
            }
        }
        return nil
    }

    /// The prohibited mentions: the unqualified name `xmlns`, or any name in
    /// the xmlns namespace name.
    private static func xmlnsMentionProblem(localName: String?, namespaceName: String) -> String? {
        let xmlnsURI = "http://www.w3.org/2000/xmlns"
        if localName == "xmlns", namespaceName.isEmpty {
            return "an attribute must not be named 'xmlns' (4.16)"
        }
        if namespaceName == xmlnsURI || namespaceName == xmlnsURI + "/" {
            return "an attribute must not be in the xmlns namespace (4.16)"
        }
        return nil
    }

    private static func checkData(_ node: RNGTree, children: [RNGTree]) -> String? {
        guard hasNCName(node, "type") else { return "<data> needs an NCName type attribute" }
        var sawExcept = false
        for child in children {
            switch RNGNode.localName(child) {
            case "param":
                if sawExcept { return "<param> may not follow <except> in <data>" }
                guard hasNCName(child, "name") else { return "<param> needs a name attribute" }
            case "except":
                if sawExcept { return "<data> takes at most one <except>" }
                sawExcept = true
                let members = RNGNode.elementChildren(child)
                guard !members.isEmpty else { return "<except> in <data> needs content" }
                if let problem = firstViolation(members, in: .dataExcept) { return problem }
            default:
                return "<\(RNGNode.localName(child) ?? "?")> is not allowed in <data>"
            }
        }
        return nil
    }

    /// `except` in `data` admits only data, value, and choices of them (4.16).
    private static func checkDataExceptMember(_ node: RNGTree, name: String) -> String? {
        switch name {
        case "data", "value":
            return checkPattern(node, name: name)
        case "choice":
            let children = RNGNode.elementChildren(node)
            guard !children.isEmpty else { return "<choice> needs at least one pattern" }
            return firstViolation(children, in: .dataExcept)
        default:
            return "<\(name)> is not allowed inside a data except (4.16)"
        }
    }
}
