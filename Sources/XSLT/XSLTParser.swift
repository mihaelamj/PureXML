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
        /// Template instantiation nested deeper than the configured limit (the
        /// associated value), so the transform was stopped before it could
        /// overflow the stack. Reached by unbounded template recursion, e.g. a
        /// recursive named template whose depth is driven by source data.
        case recursionLimitExceeded(Int)

        public var description: String {
            switch self {
            case .notAStylesheet: "the document is not an xsl:stylesheet"
            case let .terminated(message): "transformation terminated: \(message)"
            case let .recursionLimitExceeded(limit): "template recursion exceeded the limit of \(limit)"
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
        /// Compiles one stylesheet unit, folding in `xsl:include`/`xsl:import`.
        /// Import precedences are assigned post-order over the import tree (each
        /// import lower than its importer, later siblings higher); a unit's
        /// templates carry the [low, precedence) range apply-imports searches. An
        /// included stylesheet joins the including unit at its precedence.
        static func compile(_ top: XSLTTree, loader: (String) -> String?, counter: inout Int, base: String = "", chain: Set<String> = []) -> Stylesheet {
            var parts = Parts()
            let low = counter
            var collector = XSLTUnitCollector(counter: counter, chain: chain)
            collectUnit(top, loader: loader, base: base, into: &collector, imports: &parts)
            counter = collector.counter
            let precedence = counter
            counter += 1
            // Included declarations resolve their 7.1.1 namespace nodes via the
            // weak parent chain to their own stylesheet element, retained only in
            // the otherwise-unread retainedRoots; pin it so ARC keeps it here.
            withExtendedLifetime(collector.retainedRoots) {
                for (child, base) in collector.declarations {
                    _ = absorbDeclaration(child, into: &parts, precedence: precedence, low: low, base: base)
                }
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
                    let loadedImport = loadTree(child, loader: loader, base: base)
                    if let (tree, resolved) = loadedImport, !collector.chain.contains(resolved) {
                        collector.retainedRoots.append(tree)
                        parts.fold(compile(tree, loader: loader, counter: &collector.counter, base: resolved, chain: collector.chain.union([resolved])), isImport: true)
                    }
                case "include":
                    let loadedInclude = loadTree(child, loader: loader, base: base)
                    if let (tree, resolved) = loadedInclude, !collector.chain.contains(resolved) {
                        collector.retainedRoots.append(tree)
                        // The include flattens into this unit: its href joins
                        // the chain for the nested walk and leaves with it.
                        collector.chain.insert(resolved)
                        collectUnit(tree, loader: loader, base: resolved, into: &collector, imports: &parts)
                        collector.chain.remove(resolved)
                    }
                default:
                    collector.declarations.append((child, base))
                }
            }
        }

        /// Absorbs a non-composition top-level declaration, returning whether it
        /// was one (so the caller can then try `include`/`import`).
        private static func absorbDeclaration(_ child: XSLTTree, into parts: inout Parts, precedence: Int, low: Int, base: String) -> Bool {
            switch XSLTNode.localName(child) {
            case "template": parts.templates.append(template(child, precedence: precedence, low: low, base: base))
            case "variable", "param": addGlobal(child, base, into: &parts)
            case "key": parts.keys.append(key(child))
            case "output": parts.output = parts.output.merged(with: parseOutput(child))
            case "strip-space": parts.stripSpace.formUnion(elementNames(child))
            case "preserve-space": parts.preserveSpace.formUnion(elementNames(child))
            case "attribute-set": addAttributeSet(child, into: &parts)
            case "decimal-format": parts.decimalFormats[expandedDeclaredName(child)] = decimalFormat(child)
            case "namespace-alias": addNamespaceAlias(child, into: &parts)
            default: return false
            }
            return true
        }

        /// A top-level xsl:variable or xsl:param; param names are recorded
        /// so caller-supplied values can override their defaults.
        private static func addGlobal(_ child: XSLTTree, _ base: String, into parts: inout Parts) {
            parts.globals.append(PureXML.XSLT.GlobalDeclaration(instruction: variable(child), baseURI: base))
            if XSLTNode.localName(child) == "param", let name = XSLTNode.attribute(child, "name") {
                parts.parameterNames.insert(name)
            }
        }

        /// The whitespace-separated element name tests of an `xsl:strip-space` or
        /// `xsl:preserve-space` element's `elements` attribute, each resolved to
        /// namespace form so matching is by namespace, not prefix.
        private static func elementNames(_ node: XSLTTree) -> Set<String> {
            Set((XSLTNode.attribute(node, "elements") ?? "").split(whereSeparator: \.isWhitespace).map {
                expandedSpecifier(String($0), at: node)
            })
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
                // Keyed by expanded QName; the key() function expands its name
                // argument the same way before looking the index up.
                name: expandedDeclaredName(node),
                match: XSLTNode.attribute(node, "match") ?? "",
                use: XSLTNode.attribute(node, "use") ?? ".",
            )
        }

        // MARK: Templates

        private static func template(_ node: XSLTTree, precedence: Int, low: Int, base: String) -> Template {
            let match = XSLTNode.attribute(node, "match")
            let priority = XSLTNode.attribute(node, "priority").flatMap(Double.init)
                ?? match.map(defaultPriority) ?? 0
            let parameters = XSLTNode.children(node, named: "param").map(binding)
            let body = node.children
                .filter { !(XSLTNode.isXSL($0) && XSLTNode.localName($0) == "param") }
                .compactMap(instruction)
            return Template(
                match: match,
                name: XSLTNode.attribute(node, "name").map { expandedQName($0, at: node) },
                mode: expandedMode(node),
                priority: priority,
                importPrecedence: precedence,
                importRangeLow: low,
                parameters: parameters,
                body: body,
                namespaces: inScopeNamespaces(node).filter { !$0.key.isEmpty },
                baseURI: base,
            )
        }

        private static func binding(_ node: XSLTTree) -> Binding {
            Binding(
                name: expandedDeclaredName(node),
                select: XSLTNode.attribute(node, "select"),
                body: body(node),
            )
        }

        private static func withParameters(_ node: XSLTTree) -> [Binding] {
            XSLTNode.children(node, named: "with-param").map(binding)
        }

        /// The XSLT default-priority rules for a match pattern. The priority of a
        /// single-step pattern is set by its node test, regardless of an explicit
        /// `child::` or `attribute::` axis (XSLT 1.0 5.5), so the axis is stripped
        /// before the node test is classified (`attribute::node()` is -0.5, like
        /// `node()`, not 0).
        static func defaultPriority(_ pattern: String) -> Double {
            if pattern.contains("/") || pattern.contains("[") { return 0.5 }
            let test = pattern.hasPrefix("attribute::") ? String(pattern.dropFirst(11))
                : pattern.hasPrefix("child::") ? String(pattern.dropFirst(7))
                : pattern
            if ["*", "@*", "node()", "text()", "comment()", "processing-instruction()"].contains(test) { return -0.5 }
            if test.hasSuffix(":*") { return -0.25 }
            return 0
        }

        // MARK: Bodies and instructions

        static func body(_ node: XSLTTree) -> [Instruction] {
            // Adjacent text and CDATA children are one text node in the data
            // model, so a whitespace-only run is dropped (XSLT 1.0 3.4) only when
            // the WHOLE coalesced run is whitespace: " <![CDATA[x]]> " keeps its
            // spaces because the run "x" surrounds them with non-whitespace.
            // `xml:space="preserve"` in scope keeps a whitespace-only run too.
            let preserve = preservesWhitespace(node)
            var result: [Instruction] = []
            var run = ""
            func flush() {
                if !run.isEmpty, preserve || run.unicodeScalars.contains(where: { !PureXML.Parsing.XMLCharacter.isWhitespace($0) }) { result.append(.literalText(run)) }
                run = ""
            }
            for child in node.children {
                if child.kind == .text || child.kind == .cdata {
                    run += child.value
                } else {
                    flush()
                    if let instruction = instruction(child) { result.append(instruction) }
                }
            }
            flush()
            return result
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
                    mode: expandedMode(node),
                    sorts: sorts(node),
                    parameters: withParameters(node),
                )
            case "copy-of": .copyOf(select: XSLTNode.attribute(node, "select") ?? "")
            case "call-template": .callTemplate(
                    name: expandedDeclaredName(node),
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
            .variable(name: expandedDeclaredName(node), select: XSLTNode.attribute(node, "select"), body: body(node))
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
            // Each referenced set is keyed by expanded QName, matching the
            // expansion applied to the attribute-set declaration's name.
            (XSLTNode.attribute(node, "use-attribute-sets") ?? "")
                .split(whereSeparator: \.isWhitespace)
                .map { expandedQName(String($0), at: node) }
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
                    lang: XSLTNode.attribute(sort, "lang").map(valueTemplate),
                )
            }
        }
    }
}
