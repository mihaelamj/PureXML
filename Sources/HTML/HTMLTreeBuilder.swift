/// A partially-built element on the open-element stack. File-scope and private.
private struct HTMLFrame {
    let name: String
    let attributes: [PureXML.Model.Attribute]
    var children: [PureXML.Model.Node] = []
}

extension PureXML.HTML {
    /// Builds a lenient tree from HTML tokens (the libxml2 `HTMLtree.h` model):
    /// void elements get no children and no end tag, optional-end-tag elements are
    /// closed implicitly when a conflicting tag opens, and an unmatched end tag is
    /// ignored. The result is a ``PureXML/Model/Node`` document.
    enum TreeBuilder {
        /// The formatting elements that, when closed out of order, are reconstructed
        /// for the content that follows (the HTML5 active-formatting list).
        private static let formatting: Set<String> = [
            "a", "b", "big", "code", "em", "font", "i", "nobr", "s", "small", "strike", "strong", "tt", "u",
        ]

        static func build(_ tokens: [Token]) -> PureXML.Model.Node {
            var stack: [HTMLFrame] = []
            var roots: [PureXML.Model.Node] = []
            var pending: [HTMLFrame] = []
            for token in tokens {
                apply(token, stack: &stack, roots: &roots, pending: &pending)
            }
            while !stack.isEmpty {
                pop(&stack, &roots)
            }
            return .document(roots)
        }

        private static func apply(_ token: Token, stack: inout [HTMLFrame], roots: inout [PureXML.Model.Node], pending: inout [HTMLFrame]) {
            switch token {
            case let .startTag(name, attributes, selfClosing):
                reconstruct(&stack, &pending)
                openElement(name, attributes, selfClosing: selfClosing, &stack, &roots)
            case let .endTag(name):
                closeElement(name, &stack, &roots, &pending)
            case let .text(value):
                reconstruct(&stack, &pending)
                attach(.text(value), &stack, &roots)
            case let .comment(value):
                attach(.comment(value), &stack, &roots)
            case .doctype:
                break
            }
        }

        /// Re-opens any formatting elements closed out of order, so content after
        /// them is wrapped again (the HTML5 reconstruct-active-formatting step).
        private static func reconstruct(_ stack: inout [HTMLFrame], _ pending: inout [HTMLFrame]) {
            guard !pending.isEmpty else { return }
            for frame in pending {
                stack.append(HTMLFrame(name: frame.name, attributes: frame.attributes))
            }
            pending.removeAll()
        }

        private static func openElement(
            _ name: String,
            _ attributes: [(String, String)],
            selfClosing: Bool,
            _ stack: inout [HTMLFrame],
            _ roots: inout [PureXML.Model.Node],
        ) {
            closeImplied(by: name, &stack, &roots)
            let modelAttributes = attributes.map { PureXML.Model.Attribute($0.0, $0.1) }
            if Elements.void.contains(name) || selfClosing {
                let element = PureXML.Model.Element(name: .init(name), attributes: modelAttributes)
                attach(.element(element), &stack, &roots)
            } else {
                stack.append(HTMLFrame(name: name, attributes: modelAttributes))
            }
        }

        private static func closeElement(_ name: String, _ stack: inout [HTMLFrame], _ roots: inout [PureXML.Model.Node], _ pending: inout [HTMLFrame]) {
            guard let index = stack.lastIndex(where: { $0.name == name }) else { return }
            // Formatting elements strictly above the target are implicitly closed;
            // remember them so they reconstruct for the following content.
            for frame in stack[(index + 1)...] where formatting.contains(frame.name) {
                pending.append(HTMLFrame(name: frame.name, attributes: frame.attributes))
            }
            while stack.count > index {
                pop(&stack, &roots)
            }
        }

        private static func closeImplied(by name: String, _ stack: inout [HTMLFrame], _ roots: inout [PureXML.Model.Node]) {
            guard let closes = Elements.impliedClose[name] else { return }
            while let top = stack.last, closes.contains(top.name) {
                pop(&stack, &roots)
            }
        }

        private static func pop(_ stack: inout [HTMLFrame], _ roots: inout [PureXML.Model.Node]) {
            guard let frame = stack.popLast() else { return }
            let element = PureXML.Model.Element(name: .init(frame.name), attributes: frame.attributes, children: frame.children)
            attach(.element(element), &stack, &roots)
        }

        private static func attach(_ node: PureXML.Model.Node, _ stack: inout [HTMLFrame], _ roots: inout [PureXML.Model.Node]) {
            if stack.isEmpty {
                roots.append(node)
            } else {
                stack[stack.count - 1].children.append(node)
            }
        }
    }
}
