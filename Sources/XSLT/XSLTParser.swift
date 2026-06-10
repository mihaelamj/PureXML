typealias XSLTTree = PureXML.Model.TreeNode

/// The accumulating declarations of a stylesheet as its top-level elements are
/// compiled, plus the folding of an included or imported sub-stylesheet. File
/// scope and private.
private struct Parts {
    var templates: [PureXML.XSLT.Template] = []
    var globals: [PureXML.XSLT.Instruction] = []
    var keys: [PureXML.XSLT.Key] = []
    var output = PureXML.XSLT.Output()
    var stripSpace: Set<String> = []
    var preserveSpace: Set<String> = []
    var attributeSets: [String: PureXML.XSLT.AttributeSet] = [:]
    var decimalFormats: [String: PureXML.XSLT.DecimalFormat] = [:]
    var namespaceAliases: [String: PureXML.XSLT.NamespaceAlias] = [:]

    var stylesheet: PureXML.XSLT.Stylesheet {
        PureXML.XSLT.Stylesheet(
            templates: templates,
            globals: globals,
            keys: keys,
            output: output,
            stripSpace: stripSpace,
            preserveSpace: preserveSpace,
            attributeSets: attributeSets,
            decimalFormats: decimalFormats,
            namespaceAliases: namespaceAliases,
        )
    }

    /// Folds a sub-stylesheet in: an import has lower precedence, so its globals
    /// come before and its output is overridden by this stylesheet's.
    mutating func fold(_ sub: PureXML.XSLT.Stylesheet?, isImport: Bool) {
        guard let sub else { return }
        templates += sub.templates
        keys += sub.keys
        stripSpace.formUnion(sub.stripSpace)
        preserveSpace.formUnion(sub.preserveSpace)
        attributeSets.merge(sub.attributeSets) { mine, _ in mine }
        decimalFormats.merge(sub.decimalFormats) { mine, _ in mine }
        namespaceAliases.merge(sub.namespaceAliases) { mine, _ in mine }
        globals = isImport ? sub.globals + globals : globals + sub.globals
        output = isImport ? sub.output.merged(with: output) : output.merged(with: sub.output)
    }
}

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
        static func parse(_ xsl: String, loader: (String) -> String? = { _ in nil }) throws -> Stylesheet {
            let root = try PureXML.parseTree(xsl)
            guard let top = stylesheetElement(root) else { throw XSLTError.notAStylesheet }
            return compile(top, loader: loader, precedence: 0)
        }

        private static func stylesheetElement(_ root: XSLTTree) -> XSLTTree? {
            guard let top = XSLTNode.elementChildren(root).first, XSLTNode.isXSL(top),
                  XSLTNode.localName(top) == "stylesheet" || XSLTNode.localName(top) == "transform"
            else {
                return nil
            }
            return top
        }

        /// Compiles a stylesheet element, folding in `xsl:include`/`xsl:import`.
        private static func compile(_ top: XSLTTree, loader: (String) -> String?, precedence: Int) -> Stylesheet {
            var parts = Parts()
            for child in XSLTNode.elementChildren(top) where XSLTNode.isXSL(child) {
                absorb(child, into: &parts, loader: loader, precedence: precedence)
            }
            return parts.stylesheet
        }

        private static func absorb(_ child: XSLTTree, into parts: inout Parts, loader: (String) -> String?, precedence: Int) {
            if absorbDeclaration(child, into: &parts, precedence: precedence) { return }
            switch XSLTNode.localName(child) {
            case "include": parts.fold(load(child, loader: loader, precedence: precedence), isImport: false)
            case "import": parts.fold(load(child, loader: loader, precedence: precedence - 1), isImport: true)
            default: break
            }
        }

        /// Absorbs a non-composition top-level declaration, returning whether it
        /// was one (so the caller can then try `include`/`import`).
        private static func absorbDeclaration(_ child: XSLTTree, into parts: inout Parts, precedence: Int) -> Bool {
            switch XSLTNode.localName(child) {
            case "template": parts.templates.append(template(child, precedence: precedence))
            case "variable", "param": parts.globals.append(variable(child))
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

        /// The whitespace-separated element name tests of an `xsl:strip-space` or
        /// `xsl:preserve-space` element's `elements` attribute.
        private static func elementNames(_ node: XSLTTree) -> Set<String> {
            Set((XSLTNode.attribute(node, "elements") ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
        }

        private static func load(_ node: XSLTTree, loader: (String) -> String?, precedence: Int) -> Stylesheet? {
            guard let href = XSLTNode.attribute(node, "href"), let text = loader(href),
                  let root = try? PureXML.parseTree(text), let top = stylesheetElement(root)
            else {
                return nil
            }
            return compile(top, loader: loader, precedence: precedence)
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

        private static func template(_ node: XSLTTree, precedence: Int) -> Template {
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
                parameters: parameters,
                body: body,
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

        private static func instruction(_ node: XSLTTree) -> Instruction? {
            switch node.kind {
            case .text, .cdata:
                let value = node.value
                return value.allSatisfy(\.isWhitespace) ? nil : .literalText(value)
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
            case "value-of": .valueOf(select: XSLTNode.attribute(node, "select") ?? "")
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
            case "text": .literalText(node.stringValue)
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
        parts.attributeSets[name] = PureXML.XSLT.AttributeSet(attributes: body(child), use: useAttributeSets(child))
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
