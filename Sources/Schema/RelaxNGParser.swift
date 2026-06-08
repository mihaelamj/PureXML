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

extension PureXML.Schema {
    /// Parses a RELAX NG schema in the XML syntax into a grammar: a start pattern
    /// and the named `define` patterns it refers to. The vocabulary is matched by
    /// local name. Supports `element`, `attribute`, `text`, `empty`, `notAllowed`,
    /// `group`, `choice`, `interleave`, `optional`, `zeroOrMore`, `oneOrMore`,
    /// `mixed`, `list`, `ref`, `data`, `value`, and the name classes.
    enum RelaxNGParser {
        static func parse(_ rng: String) throws -> (start: Pattern, defines: [String: Pattern]) {
            let root = try PureXML.parseTree(rng)
            guard let top = RNGNode.elementChildren(root).first else {
                throw PureXML.Schema.SchemaError.notASchema
            }
            if RNGNode.localName(top) == "grammar" {
                return grammar(top)
            }
            return (pattern(top), [:])
        }

        private static func grammar(_ node: Tree) -> (start: Pattern, defines: [String: Pattern]) {
            var defines: [String: Pattern] = [:]
            for define in RNGNode.children(node, named: "define") {
                if let name = RNGNode.attribute(define, "name") {
                    defines[name] = combined(RNGNode.elementChildren(define), .sequence)
                }
            }
            let start = RNGNode.children(node, named: "start").first
            return (start.map { combined(RNGNode.elementChildren($0), .sequence) } ?? .notAllowed, defines)
        }

        // MARK: Patterns

        private static func pattern(_ node: Tree) -> Pattern {
            leafPattern(node) ?? compositePattern(node)
        }

        /// The terminal and element/attribute patterns; nil for a compositor.
        private static func leafPattern(_ node: Tree) -> Pattern? {
            switch RNGNode.localName(node) {
            case "empty": .empty
            case "notAllowed": .notAllowed
            case "text": .text
            case "data": .data(BuiltinType(rawValue: RNGNode.strip(RNGNode.attribute(node, "type") ?? "string")) ?? .string)
            case "value": .value(RNGNode.text(node))
            case "ref": .ref(RNGNode.attribute(node, "name") ?? "")
            case "element": element(node)
            case "attribute": attribute(node)
            default: nil
            }
        }

        /// The compositor and quantifier patterns.
        private static func compositePattern(_ node: Tree) -> Pattern {
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

        private static func group(_ node: Tree) -> Pattern {
            combined(RNGNode.elementChildren(node), .sequence)
        }

        private static func element(_ node: Tree) -> Pattern {
            let (nameClass, contentNodes) = nameClassAndContent(node)
            return .element(nameClass, combined(contentNodes, .sequence))
        }

        private static func attribute(_ node: Tree) -> Pattern {
            let (nameClass, contentNodes) = nameClassAndContent(node)
            let content = contentNodes.isEmpty ? Pattern.text : combined(contentNodes, .sequence)
            return .attribute(nameClass, content)
        }

        /// Splits an `element`/`attribute` node into its name class and its pattern
        /// children: a `name` attribute gives the class and all children are
        /// content; otherwise the first child is the name class.
        private static func nameClassAndContent(_ node: Tree) -> (NameClass, [Tree]) {
            let children = RNGNode.elementChildren(node)
            if let name = RNGNode.attribute(node, "name") {
                let namespace = RNGNode.attribute(node, "ns") ?? ""
                return (.name(namespace: namespace, localName: name), children)
            }
            guard let first = children.first else { return (.anyName, []) }
            return (nameClass(first), Array(children.dropFirst()))
        }

        // MARK: Combinators and name classes

        private static func combined(_ nodes: [Tree], _ compositor: Compositor) -> Pattern {
            let patterns = nodes.map(pattern)
            let identity: Pattern = compositor == .choice ? .notAllowed : .empty
            guard let first = patterns.first else { return identity }
            return patterns.dropFirst().reduce(first) { combine($0, $1, compositor) }
        }

        private static func combine(_ lhs: Pattern, _ rhs: Pattern, _ compositor: Compositor) -> Pattern {
            switch compositor {
            case .sequence: .group(lhs, rhs)
            case .choice: .choice(lhs, rhs)
            case .all: .interleave(lhs, rhs)
            }
        }

        private static func nameClass(_ node: Tree) -> NameClass {
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

        private static func anyName(_ node: Tree) -> NameClass {
            guard let except = RNGNode.children(node, named: "except").first,
                  let inner = RNGNode.elementChildren(except).first
            else {
                return .anyName
            }
            return .anyNameExcept(nameClass(inner))
        }

        private static func nameClassChoice(_ nodes: [Tree]) -> NameClass {
            let classes = nodes.map(nameClass)
            guard let first = classes.first else { return .anyName }
            return classes.dropFirst().reduce(first) { .choice($0, $1) }
        }
    }
}
