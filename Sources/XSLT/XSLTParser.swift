private typealias Tree = PureXML.Model.TreeNode

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

    var stylesheet: PureXML.XSLT.Stylesheet {
        PureXML.XSLT.Stylesheet(
            templates: templates,
            globals: globals,
            keys: keys,
            output: output,
            stripSpace: stripSpace,
            preserveSpace: preserveSpace,
            attributeSets: attributeSets,
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
        globals = isImport ? sub.globals + globals : globals + sub.globals
        output = isImport ? sub.output.merged(with: output) : output.merged(with: sub.output)
    }
}

/// Tree helpers for the XSLT parser. File-scope and private.
private enum XSLTNode {
    static let namespace = "http://www.w3.org/1999/XSL/Transform"

    static func localName(_ node: Tree) -> String? {
        node.name?.localName
    }

    static func isXSL(_ node: Tree) -> Bool {
        node.kind == .element && (node.name?.namespaceURI == namespace || node.name?.prefix == "xsl")
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

        private static func stylesheetElement(_ root: Tree) -> Tree? {
            guard let top = XSLTNode.elementChildren(root).first, XSLTNode.isXSL(top),
                  XSLTNode.localName(top) == "stylesheet" || XSLTNode.localName(top) == "transform"
            else {
                return nil
            }
            return top
        }

        /// Compiles a stylesheet element, recursively folding in `xsl:include`
        /// (same import precedence) and `xsl:import` (one lower) resolved through
        /// `loader`.
        private static func compile(_ top: Tree, loader: (String) -> String?, precedence: Int) -> Stylesheet {
            var parts = Parts()
            for child in XSLTNode.elementChildren(top) where XSLTNode.isXSL(child) {
                absorb(child, into: &parts, loader: loader, precedence: precedence)
            }
            return parts.stylesheet
        }

        private static func absorb(_ child: Tree, into parts: inout Parts, loader: (String) -> String?, precedence: Int) {
            switch XSLTNode.localName(child) {
            case "template": parts.templates.append(template(child, precedence: precedence))
            case "variable", "param": parts.globals.append(variable(child))
            case "key": parts.keys.append(key(child))
            case "output": parts.output = parts.output.merged(with: parseOutput(child))
            case "strip-space": parts.stripSpace.formUnion(elementNames(child))
            case "preserve-space": parts.preserveSpace.formUnion(elementNames(child))
            case "attribute-set": addAttributeSet(child, into: &parts)
            case "include": parts.fold(load(child, loader: loader, precedence: precedence), isImport: false)
            case "import": parts.fold(load(child, loader: loader, precedence: precedence - 1), isImport: true)
            default: break
            }
        }

        private static func addAttributeSet(_ child: Tree, into parts: inout Parts) {
            guard let name = XSLTNode.attribute(child, "name") else { return }
            parts.attributeSets[name] = AttributeSet(attributes: body(child), use: useAttributeSets(child))
        }

        /// The whitespace-separated element name tests of an `xsl:strip-space` or
        /// `xsl:preserve-space` element's `elements` attribute.
        private static func elementNames(_ node: Tree) -> Set<String> {
            Set((XSLTNode.attribute(node, "elements") ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
        }

        private static func load(_ node: Tree, loader: (String) -> String?, precedence: Int) -> Stylesheet? {
            guard let href = XSLTNode.attribute(node, "href"), let text = loader(href),
                  let root = try? PureXML.parseTree(text), let top = stylesheetElement(root)
            else {
                return nil
            }
            return compile(top, loader: loader, precedence: precedence)
        }

        private static func parseOutput(_ node: Tree) -> Output {
            Output(
                method: XSLTNode.attribute(node, "method"),
                indent: XSLTNode.attribute(node, "indent").map { $0 == "yes" },
                omitXMLDeclaration: XSLTNode.attribute(node, "omit-xml-declaration").map { $0 == "yes" },
                encoding: XSLTNode.attribute(node, "encoding"),
                version: XSLTNode.attribute(node, "version"),
                standalone: XSLTNode.attribute(node, "standalone").map { $0 == "yes" },
            )
        }

        private static func key(_ node: Tree) -> Key {
            Key(
                name: XSLTNode.attribute(node, "name") ?? "",
                match: XSLTNode.attribute(node, "match") ?? "",
                use: XSLTNode.attribute(node, "use") ?? ".",
            )
        }

        // MARK: Templates

        private static func template(_ node: Tree, precedence: Int) -> Template {
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

        private static func binding(_ node: Tree) -> Binding {
            Binding(
                name: XSLTNode.attribute(node, "name") ?? "",
                select: XSLTNode.attribute(node, "select"),
                body: body(node),
            )
        }

        private static func withParameters(_ node: Tree) -> [Binding] {
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

        private static func body(_ node: Tree) -> [Instruction] {
            node.children.compactMap(instruction)
        }

        private static func instruction(_ node: Tree) -> Instruction? {
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

        private static func xslInstruction(_ node: Tree) -> Instruction? {
            if let known = simpleInstruction(node) ?? structuralInstruction(node) { return known }
            // An unrecognized XSLT element instantiates its xsl:fallback children
            // (forwards-compatible processing); with none, it is dropped.
            let fallback = XSLTNode.children(node, named: "fallback").flatMap(body)
            return fallback.isEmpty ? nil : .fallback(body: fallback)
        }

        private static func simpleInstruction(_ node: Tree) -> Instruction? {
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
            case "copy": .copy(body: body(node))
            case "message": .message(terminate: XSLTNode.attribute(node, "terminate") == "yes", body: body(node))
            case "apply-imports": .applyImports
            default: nil
            }
        }

        private static func structuralInstruction(_ node: Tree) -> Instruction? {
            switch XSLTNode.localName(node) {
            case "for-each":
                .forEach(select: XSLTNode.attribute(node, "select") ?? "", sorts: sorts(node), body: body(node))
            case "if":
                .ifInstruction(test: XSLTNode.attribute(node, "test") ?? "", body: body(node))
            case "choose":
                choose(node)
            case "element":
                .element(name: valueTemplate(XSLTNode.attribute(node, "name") ?? ""), useAttributeSets: useAttributeSets(node), body: body(node))
            case "attribute":
                .attribute(name: valueTemplate(XSLTNode.attribute(node, "name") ?? ""), body: body(node))
            case "number":
                .number(
                    count: XSLTNode.attribute(node, "count"),
                    from: XSLTNode.attribute(node, "from"),
                    format: XSLTNode.attribute(node, "format") ?? "1",
                )
            case "comment":
                .comment(body: body(node))
            case "processing-instruction":
                .processingInstruction(name: valueTemplate(XSLTNode.attribute(node, "name") ?? ""), body: body(node))
            default:
                nil
            }
        }

        private static func variable(_ node: Tree) -> Instruction {
            .variable(name: XSLTNode.attribute(node, "name") ?? "", select: XSLTNode.attribute(node, "select"), body: body(node))
        }

        private static func choose(_ node: Tree) -> Instruction {
            let whens = XSLTNode.children(node, named: "when").map { branch in
                Branch(test: XSLTNode.attribute(branch, "test") ?? "", body: body(branch))
            }
            let otherwise = XSLTNode.children(node, named: "otherwise").first.map(body) ?? []
            return .choose(whens: whens, otherwise: otherwise)
        }

        private static func literalElement(_ node: Tree) -> Instruction {
            guard let name = node.name else { return .literalText("") }
            // xmlns declarations and the special xsl:* attributes (use-attribute-sets,
            // version, exclude-result-prefixes …) are not copied to the output.
            let attributes = node.attributes
                .filter { $0.name.prefix != "xmlns" && !($0.name.prefix == nil && $0.name.localName == "xmlns") && $0.name.prefix != "xsl" }
                .map { LiteralAttribute(name: $0.name, value: valueTemplate($0.value)) }
            return .literalElement(name: name, attributes: attributes, useAttributeSets: useAttributeSets(node), body: body(node))
        }

        /// The whitespace-separated names of `[xsl:]use-attribute-sets` on `node`.
        private static func useAttributeSets(_ node: Tree) -> [String] {
            (XSLTNode.attribute(node, "use-attribute-sets") ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        }

        private static func sorts(_ node: Tree) -> [Sort] {
            XSLTNode.children(node, named: "sort").map { sort in
                Sort(
                    select: XSLTNode.attribute(sort, "select") ?? ".",
                    descending: XSLTNode.attribute(sort, "order") == "descending",
                    numeric: XSLTNode.attribute(sort, "data-type") == "number",
                )
            }
        }

        // MARK: Attribute value templates

        static func valueTemplate(_ string: String) -> ValueTemplate {
            var parts: [ValuePart] = []
            var literal = ""
            let characters = Array(string)
            var index = 0
            while index < characters.count {
                let character = characters[index]
                if character == "{", index + 1 < characters.count, characters[index + 1] == "{" {
                    literal.append("{")
                    index += 2
                    continue
                }
                if character == "}", index + 1 < characters.count, characters[index + 1] == "}" {
                    literal.append("}")
                    index += 2
                    continue
                }
                if character == "{" {
                    if !literal.isEmpty { parts.append(.literal(literal))
                        literal = ""
                    }
                    index += 1
                    var expression = ""
                    while index < characters.count, characters[index] != "}" {
                        expression.append(characters[index])
                        index += 1
                    }
                    index += 1
                    parts.append(.expression(expression))
                    continue
                }
                literal.append(character)
                index += 1
            }
            if !literal.isEmpty { parts.append(.literal(literal)) }
            return parts
        }
    }
}
