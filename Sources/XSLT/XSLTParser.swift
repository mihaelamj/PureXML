typealias XSLTTree = PureXML.Model.TreeNode

// The accumulating declarations of a stylesheet as its top-level elements are
// compiled, plus the folding of an included or imported sub-stylesheet. File
// scope and private.

/// XSLTTree helpers for the XSLT parser. File-scope and private.
enum XSLTNode {
    static let namespace = "http://www.w3.org/1999/XSL/Transform"

    static func localName(_ node: XSLTTree) -> String? {
        node.name?.localName
    }

    static func isXSL(_ node: XSLTTree) -> Bool {
        node.kind == .element && (node.name?.namespaceURI == namespace || node.name?.prefix == "xsl")
    }

    static func attribute(_ node: XSLTTree, _ name: String) -> String? {
        node.attributes.first { $0.name.localName == name }?.value
    }

    static func elementChildren(_ node: XSLTTree) -> [XSLTTree] {
        node.children.filter { $0.kind == .element }
    }

    static func children(_ node: XSLTTree, named name: String) -> [XSLTTree] {
        elementChildren(node).filter { localName($0) == name }
    }
}

public extension PureXML.XSLT {
    /// Errors compiling or running a stylesheet.
    enum XSLTError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case notAStylesheet
        /// An `xsl:message terminate="yes"` ended the transformation with this text.
        case terminated(String)

        public var description: String {
            switch self {
            case .notAStylesheet: "the document is not an xsl:stylesheet"
            case let .terminated(message): "transformation terminated: \(message)"
            }
        }
    }
}

extension PureXML.XSLT {
    /// Parses an XSLT 1.0 stylesheet document into a ``Stylesheet``: its template
    /// rules (with computed default priorities) and global variables. The XSLT
    /// vocabulary is recognized by namespace or the `xsl` prefix; other elements
    /// are literal result elements.
    enum XSLTParser {
        /// Compiles a stylesheet element, folding in `xsl:include`/`xsl:import`.
        /// Compiles one stylesheet unit. Import precedences are assigned in
        /// post-order over the import tree (each import lower than its
        /// importer, later sibling imports higher than earlier ones), and a
        /// unit's templates carry the [low, precedence) range of its own
        /// import subtree, the set apply-imports searches. An included
        /// stylesheet's declarations join the including unit at its
        /// precedence; its imports join the including unit's import list.
        static func compile(_ top: XSLTTree, loader: (String) -> String?, counter: inout Int, base: String = "") -> Stylesheet {
            var parts = Parts()
            let low = counter
            var collector = XSLTUnitCollector(counter: counter)
            collectUnit(top, loader: loader, base: base, into: &collector, imports: &parts)
            counter = collector.counter
            let precedence = counter
            counter += 1
            for (child, _) in collector.declarations {
                _ = absorbDeclaration(child, into: &parts, precedence: precedence, low: low)
            }
            return parts.stylesheet
        }

        // Walks a unit's xsl children: imports compile immediately (in
        // document order, so later ones take higher precedence), includes
        // flatten recursively, other declarations are queued for the unit's
        // own precedence.

        private static func collectUnit(
            _ top: XSLTTree,
            loader: (String) -> String?,
            base: String,
            into collector: inout XSLTUnitCollector,
            imports parts: inout Parts,
        ) {
            for child in XSLTNode.elementChildren(top) where XSLTNode.isXSL(child) {
                switch XSLTNode.localName(child) {
                case "import":
                    parts.fold(load(child, loader: loader, counter: &collector.counter, base: base), isImport: true)
                case "include":
                    if let (tree, resolved) = loadTree(child, loader: loader, base: base) {
                        collector.retainedRoots.append(tree)
                        collectUnit(tree, loader: loader, base: resolved, into: &collector, imports: &parts)
                    }
                default:
                    collector.declarations.append((child, base))
                }
            }
        }

        /// Absorbs a non-composition top-level declaration, returning whether it
        /// was one (so the caller can then try `include`/`import`).
        private static func absorbDeclaration(_ child: XSLTTree, into parts: inout Parts, precedence: Int, low: Int) -> Bool {
            switch XSLTNode.localName(child) {
            case "template": parts.templates.append(template(child, precedence: precedence, low: low))
            case "variable", "param": addGlobal(child, into: &parts)
            case "key": parts.keys.append(key(child))
            case "output": parts.output = parts.output.merged(with: parseOutput(child))
            case "strip-space": parts.stripSpace.formUnion(elementNames(child))
            case "preserve-space": parts.preserveSpace.formUnion(elementNames(child))
            case "attribute-set": addAttributeSet(child, into: &parts)
            case "decimal-format": parts.decimalFormats[XSLTNode.attribute(child, "name") ?? ""] = decimalFormat(child)
            case "namespace-alias": addNamespaceAlias(child, into: &parts)
            default: return false
            }
            return true
        }

        /// A top-level xsl:variable or xsl:param; param names are recorded
        /// so caller-supplied values can override their defaults.
        private static func addGlobal(_ child: XSLTTree, into parts: inout Parts) {
            parts.globals.append(variable(child))
            if XSLTNode.localName(child) == "param", let name = XSLTNode.attribute(child, "name") {
                parts.parameterNames.insert(name)
            }
        }

        /// The whitespace-separated element name tests of an `xsl:strip-space` or
        /// `xsl:preserve-space` element's `elements` attribute.
        private static func elementNames(_ node: XSLTTree) -> Set<String> {
            Set((XSLTNode.attribute(node, "elements") ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
        }

        /// Loads an include/import target's stylesheet element: the href
        /// resolves against the importing stylesheet's own URI, which becomes
        /// the base for the loaded sheet's own includes and imports.
        private static func loadTree(_ node: XSLTTree, loader: (String) -> String?, base: String) -> (XSLTTree, String)? {
            guard let href = XSLTNode.attribute(node, "href") else { return nil }
            let resolved = base.isEmpty ? href : PureXML.XInclude.URIReference.resolve(href, against: base)
            guard let text = loader(resolved),
                  let root = try? PureXML.parseTree(text, limits: .init(allowDoctype: true)), let top = stylesheetElement(root)
            else {
                return nil
            }
            return (top, resolved)
        }

        private static func load(_ node: XSLTTree, loader: (String) -> String?, counter: inout Int, base: String) -> Stylesheet? {
            guard let (top, resolved) = loadTree(node, loader: loader, base: base) else { return nil }
            return compile(top, loader: loader, counter: &counter, base: resolved)
        }

        private static func parseOutput(_ node: XSLTTree) -> Output {
            Output(
                method: XSLTNode.attribute(node, "method"),
                indent: XSLTNode.attribute(node, "indent").map { $0 == "yes" },
                omitXMLDeclaration: XSLTNode.attribute(node, "omit-xml-declaration").map { $0 == "yes" },
                encoding: XSLTNode.attribute(node, "encoding"),
                version: XSLTNode.attribute(node, "version"),
                standalone: XSLTNode.attribute(node, "standalone").map { $0 == "yes" },
                doctypePublic: XSLTNode.attribute(node, "doctype-public"),
                doctypeSystem: XSLTNode.attribute(node, "doctype-system"),
                cdataSectionElements: Set((XSLTNode.attribute(node, "cdata-section-elements") ?? "").split(whereSeparator: \.isWhitespace).map(String.init)),
            )
        }

        private static func key(_ node: XSLTTree) -> Key {
            Key(
                name: XSLTNode.attribute(node, "name") ?? "",
                match: XSLTNode.attribute(node, "match") ?? "",
                use: XSLTNode.attribute(node, "use") ?? ".",
            )
        }

        // MARK: Templates

        private static func template(_ node: XSLTTree, precedence: Int, low: Int) -> Template {
            let match = XSLTNode.attribute(node, "match")
            let priority = XSLTNode.attribute(node, "priority").flatMap(Double.init)
                ?? match.map(defaultPriority) ?? 0
            let parameters = XSLTNode.children(node, named: "param").map(binding)
            let body = node.children
                .filter { !(XSLTNode.isXSL($0) && XSLTNode.localName($0) == "param") }
                .compactMap(instruction)
            return Template(
                match: match,
                name: XSLTNode.attribute(node, "name"),
                mode: XSLTNode.attribute(node, "mode"),
                priority: priority,
                importPrecedence: precedence,
                importRangeLow: low,
                parameters: parameters,
                body: body,
                namespaces: inScopeNamespaces(node).filter { !$0.key.isEmpty },
            )
        }

        private static func binding(_ node: XSLTTree) -> Binding {
            Binding(
                name: XSLTNode.attribute(node, "name") ?? "",
                select: XSLTNode.attribute(node, "select"),
                body: body(node),
            )
        }

        private static func withParameters(_ node: XSLTTree) -> [Binding] {
            XSLTNode.children(node, named: "with-param").map(binding)
        }

        /// The XSLT default-priority rules for a match pattern.
        static func defaultPriority(_ pattern: String) -> Double {
            if pattern.contains("/") || pattern.contains("[") { return 0.5 }
            if ["*", "@*", "node()", "text()", "comment()"].contains(pattern) { return -0.5 }
            if pattern.hasSuffix(":*") { return -0.25 }
            return 0
        }

        // MARK: Bodies and instructions

        static func body(_ node: XSLTTree) -> [Instruction] {
            node.children.compactMap(instruction)
        }

        static func instruction(_ node: XSLTTree) -> Instruction? {
            switch node.kind {
            case .text, .cdata:
                let value = node.value
                return value.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" } ? nil : .literalText(value)
            case .element:
                return XSLTNode.isXSL(node) ? xslInstruction(node) : literalElement(node)
            default:
                return nil
            }
        }

        private static func xslInstruction(_ node: XSLTTree) -> Instruction? {
            if let known = simpleInstruction(node) ?? structuralInstruction(node) { return known }
            // An unrecognized XSLT element instantiates its xsl:fallback children
            // (forwards-compatible processing); with none, it is dropped.
            let fallback = XSLTNode.children(node, named: "fallback").flatMap(body)
            return fallback.isEmpty ? nil : .fallback(body: fallback)
        }

        private static func simpleInstruction(_ node: XSLTTree) -> Instruction? {
            switch XSLTNode.localName(node) {
            case "value-of": .valueOf(
                    select: XSLTNode.attribute(node, "select") ?? "",
                    raw: XSLTNode.attribute(node, "disable-output-escaping") == "yes",
                )
            case "apply-templates": .applyTemplates(
                    select: XSLTNode.attribute(node, "select"),
                    mode: XSLTNode.attribute(node, "mode"),
                    sorts: sorts(node),
                    parameters: withParameters(node),
                )
            case "copy-of": .copyOf(select: XSLTNode.attribute(node, "select") ?? "")
            case "call-template": .callTemplate(
                    name: XSLTNode.attribute(node, "name") ?? "",
                    parameters: withParameters(node),
                )
            case "text": .literalText(
                    XSLTNode.attribute(node, "disable-output-escaping") == "yes"
                        ? PureXML.XSLT.RawText.marked(node.stringValue)
                        : node.stringValue,
                )
            case "variable", "param": variable(node)
            case "copy": .copy(useAttributeSets: useAttributeSets(node), body: body(node))
            case "message": .message(terminate: XSLTNode.attribute(node, "terminate") == "yes", body: body(node))
            case "apply-imports": .applyImports
            default: nil
            }
        }

        private static func variable(_ node: XSLTTree) -> Instruction {
            .variable(name: XSLTNode.attribute(node, "name") ?? "", select: XSLTNode.attribute(node, "select"), body: body(node))
        }

        static func choose(_ node: XSLTTree) -> Instruction {
            let whens = XSLTNode.children(node, named: "when").map { branch in
                Branch(test: XSLTNode.attribute(branch, "test") ?? "", body: body(branch))
            }
            let otherwise = XSLTNode.children(node, named: "otherwise").first.map(body) ?? []
            return .choose(whens: whens, otherwise: otherwise)
        }

        private static func literalElement(_ node: XSLTTree) -> Instruction {
            guard let name = node.name else { return .literalText("") }
            // xmlns declarations and the special xsl:* attributes (use-attribute-sets,
            // version, exclude-result-prefixes …) are not copied to the output.
            let attributes = node.attributes
                .filter { $0.name.prefix != "xmlns" && !($0.name.prefix == nil && $0.name.localName == "xmlns") && $0.name.prefix != "xsl" }
                .map { LiteralAttribute(name: $0.name, value: valueTemplate($0.value)) }
            return .literalElement(
                name: name,
                attributes: attributes,
                namespaces: copiedNamespaces(node),
                useAttributeSets: useAttributeSets(node),
                body: body(node),
            )
        }

        /// The whitespace-separated names of `[xsl:]use-attribute-sets` on `node`.
        static func useAttributeSets(_ node: XSLTTree) -> [String] {
            (XSLTNode.attribute(node, "use-attribute-sets") ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        }

        private static func caseOrder(_ node: XSLTTree) -> PureXML.XSLT.CaseOrder? {
            switch XSLTNode.attribute(node, "case-order") {
            case "upper-first": .upperFirst
            case "lower-first": .lowerFirst
            default: nil
            }
        }

        static func sorts(_ node: XSLTTree) -> [Sort] {
            XSLTNode.children(node, named: "sort").map { sort in
                Sort(
                    select: XSLTNode.attribute(sort, "select") ?? ".",
                    descending: XSLTNode.attribute(sort, "order") == "descending",
                    numeric: XSLTNode.attribute(sort, "data-type") == "number",
                    caseOrder: caseOrder(sort),
                )
            }
        }
    }
}

/// Top-level declaration helpers for ``XSLTParser``, kept in an extension so the
/// parser enum stays within the type-body length budget.
private extension PureXML.XSLT.XSLTParser {
    /// Records an `xsl:namespace-alias`: the namespace bound to `stylesheet-prefix`
    /// is rewritten to the one bound to `result-prefix` (with that prefix) on output.
    static func addNamespaceAlias(_ child: XSLTTree, into parts: inout Parts) {
        let stylePrefix = XSLTNode.attribute(child, "stylesheet-prefix") ?? "#default"
        let resultPrefix = XSLTNode.attribute(child, "result-prefix") ?? "#default"
        let key = resolvePrefix(stylePrefix, at: child) ?? ""
        parts.namespaceAliases[key] = PureXML.XSLT.NamespaceAlias(
            uri: resolvePrefix(resultPrefix, at: child),
            prefix: resultPrefix == "#default" ? nil : resultPrefix,
        )
    }

    /// Resolves a namespace prefix (or `#default`) to its URI from the `xmlns`
    /// declarations in scope at `node`, walking up to the stylesheet element.
    static func resolvePrefix(_ prefix: String, at node: XSLTTree) -> String? {
        var current: XSLTTree? = node
        while let element = current {
            for attribute in element.attributes {
                let isDefault = prefix == "#default" && attribute.name.prefix == nil && attribute.name.localName == "xmlns"
                let isPrefixed = attribute.name.prefix == "xmlns" && attribute.name.localName == prefix
                if isDefault || isPrefixed { return attribute.value }
            }
            current = element.parent
        }
        return nil
    }

    static func addAttributeSet(_ child: XSLTTree, into parts: inout Parts) {
        guard let name = XSLTNode.attribute(child, "name") else { return }
        // Same-name attribute sets merge (7.1.4) as ordered definitions:
        // each expands its used sets before its own attributes, and a later
        // definition's attributes override earlier same-named ones.
        let addition = PureXML.XSLT.AttributeSet(attributes: body(child), use: useAttributeSets(child))
        parts.attributeSets[name, default: []].append(addition)
    }

    /// Reads an `xsl:decimal-format`'s symbol overrides; each unset attribute
    /// keeps the XSLT standard default.
    static func decimalFormat(_ node: XSLTTree) -> PureXML.XSLT.DecimalFormat {
        var format = PureXML.XSLT.DecimalFormat()
        func char(_ name: String, _ keyPath: WritableKeyPath<PureXML.XSLT.DecimalFormat, Character>) {
            if let value = XSLTNode.attribute(node, name)?.first { format[keyPath: keyPath] = value }
        }
        char("decimal-separator", \.decimalSeparator)
        char("grouping-separator", \.groupingSeparator)
        char("percent", \.percent)
        char("per-mille", \.perMille)
        char("zero-digit", \.zeroDigit)
        char("digit", \.digit)
        char("pattern-separator", \.patternSeparator)
        char("minus-sign", \.minusSign)
        if let infinity = XSLTNode.attribute(node, "infinity") { format.infinity = infinity }
        if let notANumber = XSLTNode.attribute(node, "NaN") { format.notANumber = notANumber }
        return format
    }
}
