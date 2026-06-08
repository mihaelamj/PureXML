private typealias Tree = PureXML.Model.TreeNode

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
    /// Errors compiling a stylesheet.
    enum XSLTError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case notAStylesheet

        public var description: String {
            switch self {
            case .notAStylesheet: "the document is not an xsl:stylesheet"
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
        static func parse(_ xsl: String) throws -> Stylesheet {
            let root = try PureXML.parseTree(xsl)
            guard let top = XSLTNode.elementChildren(root).first, XSLTNode.isXSL(top),
                  XSLTNode.localName(top) == "stylesheet" || XSLTNode.localName(top) == "transform"
            else {
                throw XSLTError.notAStylesheet
            }
            var templates: [Template] = []
            var globals: [Instruction] = []
            for child in XSLTNode.elementChildren(top) where XSLTNode.isXSL(child) {
                switch XSLTNode.localName(child) {
                case "template": templates.append(template(child))
                case "variable", "param": globals.append(variable(child))
                default: break
                }
            }
            return Stylesheet(templates: templates, globals: globals)
        }

        // MARK: Templates

        private static func template(_ node: Tree) -> Template {
            let match = XSLTNode.attribute(node, "match")
            let priority = XSLTNode.attribute(node, "priority").flatMap(Double.init)
                ?? match.map(defaultPriority) ?? 0
            return Template(
                match: match,
                name: XSLTNode.attribute(node, "name"),
                priority: priority,
                body: body(node),
            )
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
            simpleInstruction(node) ?? structuralInstruction(node)
        }

        private static func simpleInstruction(_ node: Tree) -> Instruction? {
            switch XSLTNode.localName(node) {
            case "value-of": .valueOf(select: XSLTNode.attribute(node, "select") ?? "")
            case "apply-templates": .applyTemplates(select: XSLTNode.attribute(node, "select"), sorts: sorts(node))
            case "copy-of": .copyOf(select: XSLTNode.attribute(node, "select") ?? "")
            case "call-template": .callTemplate(name: XSLTNode.attribute(node, "name") ?? "")
            case "text": .literalText(node.stringValue)
            case "variable", "param": variable(node)
            case "copy": .copy(body: body(node))
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
                .element(name: valueTemplate(XSLTNode.attribute(node, "name") ?? ""), body: body(node))
            case "attribute":
                .attribute(name: valueTemplate(XSLTNode.attribute(node, "name") ?? ""), body: body(node))
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
            let attributes = node.attributes
                .filter { $0.name.prefix != "xmlns" && !($0.name.prefix == nil && $0.name.localName == "xmlns") }
                .map { LiteralAttribute(name: $0.name, value: valueTemplate($0.value)) }
            return .literalElement(name: name, attributes: attributes, body: body(node))
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
