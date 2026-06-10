public extension PureXML.Validation {
    /// Validates a document against an XSD while it is pulled event by event (the
    /// libxml2 `xmlTextReader` validation model), holding only the open-element
    /// stack rather than the whole tree. Each element's type is resolved from its
    /// parent's content model as it opens, and its own attributes and content-model
    /// structure are checked the moment it closes, against a shallow element
    /// synthesized from the streamed child names and text. A child's deeper
    /// validity is checked when that child closes.
    ///
    /// Type resolution covers the global root declaration, the parent content
    /// model, `xsi:type` overrides, and `typeReference` chains. Wildcard
    /// `processContents` and substitution groups stay on the tree validator.
    struct StreamingXSDValidator {
        private let validator: PureXML.Schema.ComplexValidator
        private let rootElements: [String: PureXML.Schema.ElementType]
        private let abstractElements: Set<String>
        private let targetNamespace: String?
        private var stack: [XSDStreamFrame] = []
        private var collected: [ValidationError] = []
        private var sawRoot = false

        public init(
            validator: PureXML.Schema.ComplexValidator,
            rootElements: [String: PureXML.Schema.ElementType],
            abstractElements: Set<String> = [],
            targetNamespace: String? = nil,
        ) {
            self.validator = validator
            self.rootElements = rootElements
            self.abstractElements = abstractElements
            self.targetNamespace = targetNamespace
        }

        /// Feeds one parse event into the validator.
        public mutating func consume(_ event: PureXML.Parsing.Event) {
            switch event {
            case let .startElement(name, attributes):
                open(name, attributes)
            case let .characters(text), let .cdata(text):
                if !stack.isEmpty { stack[stack.count - 1].text += text }
            case .endElement:
                close()
            case .comment, .processingInstruction:
                break
            }
        }

        /// The complete error set. Call after the last event.
        public mutating func finish() -> [ValidationError] {
            if !sawRoot {
                collected.append(ValidationError(reason: "the document has no root element", at: []))
            }
            return collected
        }

        // MARK: Internals

        private mutating func open(_ name: PureXML.Model.QualifiedName, _ attributes: [PureXML.Model.Attribute]) {
            let path = openPath(name)
            let declared = resolveDeclared(name, path: path)
            if !stack.isEmpty {
                stack[stack.count - 1].childElements.append(PureXML.Model.Element(name: name))
            }
            let probe = PureXML.Model.Element(name: name, attributes: attributes)
            let effective = declared.map { validator.effectiveType($0, of: probe) }
            stack.append(XSDStreamFrame(name: name, attributes: attributes, effective: effective, path: path))
        }

        private mutating func close() {
            guard let frame = stack.popLast() else { return }
            if let effective = frame.effective {
                // Apply the streaming content check as a composable Validation value
                // (the OpenAPIKit idiom), not a bare method call.
                let subject = PureXML.Schema.ResolvedElement(element: frame.synthesized(), type: effective)
                collected += PureXML.Schema.ComplexValidator.shallowValidity.apply(to: subject, at: frame.path, in: validator)
            }
        }

        /// The declared type for an opening element: the global declaration for the
        /// root (with the root-level prolog checks), or the parent content model's
        /// child type otherwise. Records prolog errors and returns nil when the
        /// element has no type to validate against.
        private mutating func resolveDeclared(_ name: PureXML.Model.QualifiedName, path: [PathKey]) -> PureXML.Schema.ElementType? {
            guard stack.isEmpty else {
                return stack.last?.effective.flatMap { validator.childType(of: $0, child: name) }
            }
            sawRoot = true
            guard let declaration = rootElements[name.localName] else {
                collected.append(ValidationError(reason: "no element declaration for '\(name.localName)'", at: path))
                return nil
            }
            if abstractElements.contains(name.localName) {
                collected.append(ValidationError(reason: "abstract element '\(name.localName)' must not appear in an instance", at: path))
                return nil
            }
            if let target = targetNamespace, !target.isEmpty, name.namespaceURI != target {
                collected.append(ValidationError(reason: "root element '\(name.localName)' is not in the schema target namespace '\(target)'", at: path))
                return nil
            }
            return declaration
        }

        /// The coding path for an opening element: the root unindexed, a child with
        /// a one-based occurrence index (the `xmlGetNodePath` convention).
        private mutating func openPath(_ name: PureXML.Model.QualifiedName) -> [PathKey] {
            let key = name.description
            guard !stack.isEmpty else { return [.element(key)] }
            let parent = stack.count - 1
            stack[parent].childCounts[key, default: 0] += 1
            let index = stack[parent].childCounts[key] ?? 1
            return stack[parent].path + [.element(key, index: index)]
        }
    }
}

/// One open element while streaming an XSD: its name, attributes, resolved type,
/// coding path, and the direct-child placeholders and text accumulated until it
/// closes. Only names and text are needed for the shallow content check.
private struct XSDStreamFrame {
    let name: PureXML.Model.QualifiedName
    let attributes: [PureXML.Model.Attribute]
    let effective: PureXML.Schema.ElementType?
    let path: [PureXML.Validation.PathKey]
    var childElements: [PureXML.Model.Element] = []
    var childCounts: [String: Int] = [:]
    var text = ""

    /// A shallow element reproducing what the content and attribute checks read:
    /// the direct child element names and the concatenated text.
    func synthesized() -> PureXML.Model.Element {
        let children: [PureXML.Model.Node] = childElements.map { .element($0) }
            + (text.isEmpty ? [] : [.text(text)])
        return PureXML.Model.Element(name: name, attributes: attributes, children: children)
    }
}
