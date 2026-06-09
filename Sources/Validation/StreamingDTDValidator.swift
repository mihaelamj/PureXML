public extension PureXML.Validation {
    /// Validates a document against a DTD while it is pulled event by event, the
    /// libxml2 `xmlTextReader` validation model. Only the open-element stack is
    /// retained (each open element accumulates its direct-child names and a text
    /// flag), never the whole tree: an element's content model and attributes are
    /// checked the moment it closes, then its frame is dropped. Errors carry a
    /// libxml2 `xmlGetNodePath`-style coding path (every child step indexed).
    ///
    /// This reuses the exact per-element DTD rules (``DTD/contentModel`` and the
    /// attribute rules), applied to a shallow element synthesized from the
    /// streamed names, so streaming and tree validation agree. Document-scoped
    /// ID/IDREF integrity, which needs whole-document state, stays on the tree
    /// validator and is tracked separately.
    struct StreamingDTDValidator {
        private let schema: DTDSchema
        private let rules: [Validation<PureXML.Model.Element, DTDSchema>]
        private var stack: [StreamingDTDFrame] = []
        private var collected: [ValidationError] = []
        // Document-scoped ID/IDREF state, bounded to the identifier values, not
        // the tree. IDREFs may point forward, so they resolve at finish().
        private var idCounts: [String: Int] = [:]
        private var idDuplicatePath: [String: [PathKey]] = [:]
        private var pendingReferences: [StreamingIDReference] = []

        public init(schema: DTDSchema, strict: Bool = false) {
            self.schema = schema
            var rules: [Validation<PureXML.Model.Element, DTDSchema>] = [
                DTD.contentModel,
                DTD.requiredAttributes,
                DTD.fixedAttributeValues,
                DTD.enumeratedAttributeValues,
                DTD.tokenizedAttributeTypes,
                DTD.notationAttributes,
            ]
            if strict { rules.append(DTD.undeclaredElement) }
            self.rules = rules
        }

        /// Feeds one parse event into the validator.
        public mutating func consume(_ event: PureXML.Parsing.Event) {
            switch event {
            case let .startElement(name, attributes):
                stack.append(StreamingDTDFrame(name: name, attributes: attributes, path: openPath(name)))
            case let .characters(text), let .cdata(text):
                if !stack.isEmpty, text.contains(where: { !$0.isWhitespace }) {
                    stack[stack.count - 1].hasText = true
                }
            case .endElement:
                closeTop()
            case .comment, .processingInstruction:
                break
            }
        }

        /// The per-element errors found so far (content models and attributes).
        /// Document-scoped ID/IDREF errors are added by ``finish()``.
        public var errors: [ValidationError] {
            collected
        }

        /// The complete error set, including the document-scoped ID/IDREF checks
        /// that can only be resolved once every element has been seen. Call after
        /// the last event.
        public mutating func finish() -> [ValidationError] {
            var result = collected
            for (value, count) in idCounts where count > 1 {
                result.append(ValidationError(
                    reason: "duplicate ID '\(value)' (declared \(count) times)",
                    at: idDuplicatePath[value] ?? [],
                ))
            }
            for reference in pendingReferences where idCounts[reference.value] == nil {
                result.append(ValidationError(
                    reason: "IDREF '\(reference.value)' on <\(reference.element)> matches no ID",
                    at: reference.path,
                ))
            }
            return result
        }

        // MARK: Internals

        /// The coding path for an opening element, recording it as a child of the
        /// current open element with a one-based occurrence index (the
        /// `xmlGetNodePath` convention).
        private mutating func openPath(_ name: PureXML.Model.QualifiedName) -> [PathKey] {
            let key = name.description
            guard !stack.isEmpty else { return [.element(key)] }
            let parent = stack.count - 1
            stack[parent].childCounts[key, default: 0] += 1
            stack[parent].childNames.append(key)
            let index = stack[parent].childCounts[key] ?? 1
            return stack[parent].path + [.element(key, index: index)]
        }

        /// Validates the closing element against the per-element DTD rules, using a
        /// shallow element synthesized from the streamed child names and text flag.
        private mutating func closeTop() {
            guard let frame = stack.popLast() else { return }
            let children: [PureXML.Model.Node] = frame.childNames.map { .element(PureXML.Model.Element($0)) }
                + (frame.hasText ? [.text("x")] : [])
            let element = PureXML.Model.Element(name: frame.name, attributes: frame.attributes, children: children)
            collected += rules.flatMap { $0.apply(to: element, at: frame.path, in: schema) }
            collectIdentifiers(frame)
        }

        /// Records the closing element's ID and IDREF attribute values, so the
        /// document-scoped ID/IDREF integrity check can run at ``finish()``. A
        /// duplicate ID is located at its repeat occurrence; an IDREF at the
        /// element that carries it.
        private mutating func collectIdentifiers(_ frame: StreamingDTDFrame) {
            let name = frame.name.description
            guard let declarations = schema.attributes[name] else { return }
            for declaration in declarations {
                guard let value = frame.attributes.first(where: {
                    $0.name.description == declaration.name || $0.name.localName == declaration.name
                })?.value else { continue }
                switch declaration.type {
                case .id:
                    idCounts[value, default: 0] += 1
                    if idCounts[value] == 2 { idDuplicatePath[value] = frame.path }
                case .idReference:
                    pendingReferences.append(StreamingIDReference(value: value, element: name, path: frame.path))
                case .idReferences:
                    for token in value.split(whereSeparator: { $0.isWhitespace }) {
                        pendingReferences.append(StreamingIDReference(value: String(token), element: name, path: frame.path))
                    }
                case .cdata, .enumeration, .notation, .nmToken, .nmTokens, .entity, .entities:
                    break
                }
            }
        }
    }
}

public extension PureXML {
    /// Validates `xml` against `dtd` while pulling it event by event, the libxml2
    /// `xmlTextReader` validation model. Returns located errors. Memory is bounded
    /// to the open-element stack, never the whole tree.
    static func validate(
        streaming xml: String,
        dtd: Validation.DTDSchema,
        strict: Bool = false,
        limits: Parsing.Limits = .default,
    ) throws -> [Validation.ValidationError] {
        var validator = Validation.StreamingDTDValidator(schema: dtd, strict: strict)
        var reader = events(xml, limits: limits)
        while let event = try reader.next() {
            validator.consume(event)
        }
        return validator.finish()
    }
}

/// A pending IDREF awaiting resolution at the end of the stream: the referenced
/// value, the element that carries it, and that element's coding path.
private struct StreamingIDReference {
    let value: String
    let element: String
    let path: [PureXML.Validation.PathKey]
}

/// One open element while streaming: its name and attributes, the coding path to
/// it, and the direct-child names and text flag accumulated until it closes.
private struct StreamingDTDFrame {
    let name: PureXML.Model.QualifiedName
    let attributes: [PureXML.Model.Attribute]
    let path: [PureXML.Validation.PathKey]
    var childNames: [String] = []
    var childCounts: [String: Int] = [:]
    var hasText = false
}
