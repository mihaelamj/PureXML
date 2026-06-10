/// The name-class, grammar-component, and shared checks of the RELAX NG
/// grammar validator, split from the dispatch for the length caps.
extension RelaxNGGrammarCheck {
    // MARK: Name classes

    static func checkNameClass(_ node: RNGTree, name: String) -> String? {
        let children = RNGNode.elementChildren(node)
        switch name {
        case "name":
            return checkNameElement(node, children: children)
        case "anyName", "nsName":
            return checkInfiniteNameClass(node, name: name, children: children)
        case "choice":
            guard !children.isEmpty else { return "<choice> needs at least one name class" }
            return firstViolation(children, in: .nameClass)
        default:
            return "<\(name)> is not a name class"
        }
    }

    private static func checkNameElement(_ node: RNGTree, children: [RNGTree]) -> String? {
        guard children.isEmpty else { return "<name> holds text only" }
        let value = RNGNode.text(node)
        guard isQName(value) else { return "<name> must hold a QName" }
        if value.contains(":"), RNGNode.resolveQName(value, at: node) == nil {
            return "the prefix of '\(value)' is not declared"
        }
        return nil
    }

    private static func checkInfiniteNameClass(_: RNGTree, name: String, children: [RNGTree]) -> String? {
        for child in children {
            guard RNGNode.localName(child) == "except" else {
                return "<\(name)> admits only an <except> child"
            }
        }
        if children.count > 1 { return "<\(name)> takes at most one <except>" }
        guard let except = children.first else { return nil }
        let members = RNGNode.elementChildren(except)
        guard !members.isEmpty else { return "<except> needs content" }
        return firstViolation(members, in: name == "anyName" ? .exceptInAnyName : .exceptInNsName)
    }

    // MARK: Grammar components

    static func checkGrammarComponent(_ node: RNGTree, name: String, allowIncludes: Bool) -> String? {
        let children = RNGNode.elementChildren(node)
        switch name {
        case "start", "define":
            return checkCombiningComponent(node, name: name, children: children)
        case "div":
            return firstViolation(children, in: allowIncludes ? .grammarContent : .includeContent)
        case "include" where allowIncludes:
            guard RNGNode.attribute(node, "href") != nil else { return "<include> needs an href attribute" }
            return firstViolation(children, in: .includeContent)
        default:
            return "<\(name)> is not allowed in this grammar context"
        }
    }

    /// `start` takes exactly one pattern; `define` needs a name and at least
    /// one pattern; both may carry a combine method.
    private static func checkCombiningComponent(_ node: RNGTree, name: String, children: [RNGTree]) -> String? {
        if let problem = combineProblem(node) { return problem }
        if name == "start" {
            guard children.count == 1 else { return "<start> takes exactly one pattern" }
            return check(children[0], in: .pattern)
        }
        guard hasNCName(node, "name") else { return "<define> needs an NCName name attribute" }
        guard !children.isEmpty else { return "<define> needs at least one pattern" }
        return firstViolation(children, in: .pattern)
    }

    private static func combineProblem(_ node: RNGTree) -> String? {
        guard let combine = RNGNode.attribute(node, "combine"), combine != "choice", combine != "interleave" else {
            return nil
        }
        return "combine must be 'choice' or 'interleave'"
    }

    // MARK: Shared checks

    static func firstViolation(_ nodes: [RNGTree], in context: Context) -> String? {
        for node in nodes {
            if let problem = check(node, in: context) { return problem }
        }
        return nil
    }

    /// Unqualified attributes must be the ones the vocabulary allows;
    /// qualified (foreign or xml:*) attributes are annotations. The
    /// datatypeLibrary value must be an absolute, fragment-free URI, and an
    /// href must carry no fragment.
    static func attributeProblem(_ node: RNGTree, name: String) -> String? {
        let allowed = allowedAttributes[name] ?? []
        for attribute in node.attributes {
            guard attribute.name.prefix == nil else {
                if attribute.name.namespaceURI == RNGNode.relaxNGNamespace {
                    return "RELAX NG-namespace attribute '\(attribute.name.description)' is not allowed"
                }
                continue
            }
            let local = attribute.name.localName
            if local == "datatypeLibrary" {
                guard isDatatypeLibraryURI(attribute.value) else {
                    return "datatypeLibrary '\(attribute.value)' is not an absolute, fragment-free URI"
                }
                continue
            }
            if local == "href", attribute.value.contains("#") {
                return "href must not carry a fragment identifier"
            }
            guard local != "ns", local != "xmlns", !allowed.contains(local) else { continue }
            return "attribute '\(local)' is not allowed on <\(name)>"
        }
        return nil
    }

    /// RFC 3986 absolute URI without fragment: `scheme ":" ...` with a scheme
    /// of ALPHA *(ALPHA / DIGIT / "+" / "-" / "."), or the empty string for
    /// the built-in library.
    static func isDatatypeLibraryURI(_ value: String) -> Bool {
        if value.isEmpty { return true }
        guard !value.contains("#") else { return false }
        // A percent must introduce a two-digit hex escape (RFC 2396).
        var cursor = value.startIndex
        while let percent = value[cursor...].firstIndex(of: "%") {
            guard let first = value.index(percent, offsetBy: 1, limitedBy: value.endIndex),
                  let second = value.index(percent, offsetBy: 2, limitedBy: value.endIndex),
                  second < value.endIndex,
                  value[first].isHexDigit, value[second].isHexDigit
            else { return false }
            cursor = value.index(after: percent)
        }
        guard let colon = value.firstIndex(of: ":"), colon != value.startIndex,
              value.index(after: colon) < value.endIndex
        else { return false }
        let scheme = value[value.startIndex ..< colon]
        guard let first = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.dropFirst().allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "+" || character == "-" || character == ".")
        }
    }

    static let allowedAttributes: [String: Set<String>] = [
        "element": ["name"], "attribute": ["name"],
        "ref": ["name"], "parentRef": ["name"],
        "define": ["name", "combine"], "start": ["combine"],
        "data": ["type"], "value": ["type"], "param": ["name"],
        "externalRef": ["href"], "include": ["href"],
    ]

    /// Non-whitespace text is content only inside value, name, and param.
    static func textProblem(_ node: RNGTree, name: String) -> String? {
        guard !["value", "name", "param"].contains(name) else { return nil }
        for child in node.children where child.kind == .text {
            if child.stringValue.contains(where: { !$0.isWhitespace }) {
                return "text is not allowed inside <\(name)>"
            }
        }
        return nil
    }

    static func hasNCName(_ node: RNGTree, _ attribute: String) -> Bool {
        guard let value = RNGNode.attribute(node, attribute), !value.isEmpty else { return false }
        return !value.contains(":") && PureXML.Parsing.XMLCharacter.isValidName(value)
    }

    static func isQName(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, !value.isEmpty else { return false }
        return parts.allSatisfy { !$0.isEmpty && PureXML.Parsing.XMLCharacter.isValidName(String($0)) }
    }
}
