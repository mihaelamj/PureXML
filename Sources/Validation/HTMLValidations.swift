public extension PureXML.Validation {
    /// HTML conformance as composable ``Validation`` values, in the same idiom as
    /// the DTD, XSD, and structural validators: each rule is a named, removable
    /// ``Validation`` with a positive description, the ``validator()`` composes
    /// them, and failures are located ``ValidationError``s. The rules are intrinsic
    /// to HTML (no external schema), so the document type is `Void`.
    ///
    /// These check the HTML5 content-model invariants that a parsed tree can be
    /// judged against without a grammar: void elements stay empty, elements that
    /// require a particular parent appear inside one, and `id` values are unique.
    enum HTML {
        /// A void element (`br`, `img`, `input`, ...) carries no child content.
        static var voidElementsAreEmpty: Validation<PureXML.Model.Element, Void> {
            .init(description: "Void HTML elements have no content") { context in
                let name = elementName(context.subject)
                guard PureXML.HTML.Elements.void.contains(name), !context.subject.children.isEmpty else { return [] }
                return [ValidationError(reason: "void element <\(name)> must not have content", at: context.codingPath)]
            }
        }

        /// An element that requires a particular parent (`li`, `td`, `option`, ...)
        /// appears directly inside one of its allowed parents.
        static var requiredParent: Validation<PureXML.Model.Element, Void> {
            .init(description: "HTML elements appear inside their required parent") { context in
                let name = elementName(context.subject)
                guard let allowed = requiredParents[name] else { return [] }
                let parent = parentName(in: context.codingPath)
                guard parent.map({ !allowed.contains($0) }) ?? true else { return [] }
                let hint = allowed.sorted().map { "<\($0)>" }.joined(separator: ", ")
                return [ValidationError(reason: "element <\(name)> must appear inside \(hint)", at: context.codingPath)]
            }
        }

        /// Every `id` attribute value is unique in the document. Runs once over the
        /// whole tree, so it is gated to the document root.
        static var uniqueIdentifiers: Validation<PureXML.Model.Node, Void> {
            .init(
                description: "HTML id attributes are unique",
                check: { context in
                    var counts: [String: Int] = [:]
                    collectIdentifiers(context.subject, into: &counts)
                    return counts.filter { $0.value > 1 }.keys.sorted().map {
                        ValidationError(reason: "duplicate id '\($0)' (used \(counts[$0] ?? 0) times)", at: context.codingPath)
                    }
                },
                when: { $0.codingPath.isEmpty },
            )
        }

        /// A validator combining the HTML conformance rules.
        static func validator() -> Validator<Void> {
            Validator<Void>.defaults(
                nonReference: [AnyValidation(voidElementsAreEmpty), AnyValidation(requiredParent)],
                reference: [AnyValidation(uniqueIdentifiers)],
            )
        }

        /// The allowed direct parents for each element that requires one (the
        /// HTML5 content-model parent constraints).
        private static let requiredParents: [String: Set<String>] = [
            "li": ["ul", "ol", "menu"],
            "dt": ["dl"], "dd": ["dl"],
            "tr": ["table", "thead", "tbody", "tfoot"],
            "td": ["tr"], "th": ["tr"],
            "thead": ["table"], "tbody": ["table"], "tfoot": ["table"],
            "caption": ["table"], "colgroup": ["table"], "col": ["colgroup"],
            "option": ["select", "optgroup", "datalist"], "optgroup": ["select"],
            "figcaption": ["figure"], "summary": ["details"],
        ]

        private static func elementName(_ element: PureXML.Model.Element) -> String {
            element.name.description.lowercased()
        }

        /// The name of the element's direct parent from the coding path, or nil at
        /// the document root. The path ends with the element's own name, so the
        /// parent is the entry before it.
        private static func parentName(in path: [PathKey]) -> String? {
            guard path.count >= 2 else { return nil }
            return path[path.count - 2].stringValue.lowercased()
        }

        private static func collectIdentifiers(_ node: PureXML.Model.Node, into counts: inout [String: Int]) {
            switch node {
            case let .document(children):
                for child in children {
                    collectIdentifiers(child, into: &counts)
                }
            case let .element(element):
                if let id = element.attributes.first(where: { $0.name.description.lowercased() == "id" })?.value, !id.isEmpty {
                    counts[id, default: 0] += 1
                }
                for child in element.children {
                    collectIdentifiers(child, into: &counts)
                }
            case .text, .cdata, .comment, .processingInstruction:
                break
            }
        }
    }
}

public extension PureXML.HTML {
    /// The HTML conformance errors for a parsed node, in document order; empty
    /// when the tree satisfies the intrinsic HTML5 content-model rules. Built on
    /// the composable ``PureXML/Validation/HTML`` rules.
    static func validationErrors(in node: PureXML.Model.Node) -> [PureXML.Validation.ValidationError] {
        PureXML.Validation.HTML.validator().errors(for: node, in: ())
    }
}
