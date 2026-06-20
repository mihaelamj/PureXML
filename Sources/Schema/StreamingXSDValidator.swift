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
    /// model, wildcard `processContents`, `xsi:type` overrides, and
    /// `typeReference` chains. Document-scoped identity constraints are checked
    /// at the end of a streaming run when the caller supplies the parsed tree.
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
            let probe = PureXML.Model.Element(name: name, attributes: attributes)
            let parentBindings = stack.last?.bindings ?? [:]
            let bindings = PureXML.Schema.ComplexValidator.namespaceBindings(for: probe, inherited: parentBindings)
            let declared = resolveDeclared(name, path: path, root: probe, bindings: bindings)
            if !stack.isEmpty {
                stack[stack.count - 1].childElements.append(PureXML.Model.Element(name: name))
            }
            // Run the same cvc-elt.4 gate the tree path runs unconditionally for a
            // declared type: a blocked / not-derived / abstract / list-or-union /
            // anyType-for-anySimpleType xsi:type override, AND an abstract declared
            // type that requires an xsi:type but carries none. Then, only when an
            // xsi:type is present, an override naming an undeclared type is reported
            // the same way. Both resolve through the element's in-scope prefix
            // bindings, so the streaming and tree validators agree on every input.
            if let declared {
                if let xsiError = validator.xsiTypeOverrideError(declared: declared, child: probe, at: path, namespaceBindings: bindings) {
                    collected.append(xsiError)
                    stack.append(XSDStreamFrame(name: name, attributes: attributes, effective: nil, path: path, bindings: bindings))
                    return
                }
                if PureXML.Schema.ComplexValidator.xsiTypeAttributeValue(probe) != nil, validator.resolvedXsiType(probe, namespaceBindings: bindings) == nil {
                    let overriding = PureXML.Schema.ComplexValidator.xsiTypeName(probe) ?? ""
                    collected.append(ValidationError(reason: "unknown xsi:type '\(overriding)' on '\(name.localName)'", at: path))
                    stack.append(XSDStreamFrame(name: name, attributes: attributes, effective: nil, path: path, bindings: bindings))
                    return
                }
            }
            let effective = declared.map { validator.effectiveType($0, of: probe, namespaceBindings: bindings) }
            stack.append(XSDStreamFrame(name: name, attributes: attributes, effective: effective, path: path, bindings: bindings))
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
        private mutating func resolveDeclared(
            _ name: PureXML.Model.QualifiedName,
            path: [PathKey],
            root: PureXML.Model.Element,
            bindings: [String: String],
        ) -> PureXML.Schema.ElementType? {
            guard stack.isEmpty else {
                guard let parent = stack.last?.effective else { return nil }
                if let declared = validator.childType(of: parent, child: name) {
                    return declared
                }
                // A strict wildcard with no global declaration is still typed by the
                // child's own xsi:type, if present (mirrors the tree path's
                // validateWildcardChild); only without one is it undeclared.
                if let error = validator.strictWildcardError(for: name, in: parent, at: path) {
                    if let type = xsiTypeNamedType(root, bindings) {
                        return type
                    }
                    collected.append(error)
                }
                return nil
            }
            sawRoot = true
            // Resolve the root exactly as the tree path's globalElementDeclaration does
            // (namespaced identity, with the bare map used only for a no-namespace root),
            // then fall back to the type an `xsi:type` names when there is no global
            // declaration. Sharing the bare fallback across namespaces would bind a
            // foreign-namespace root to a same-local-name target-namespace element.
            let override = xsiTypeNamedType(root, bindings)
            guard let declaration = globalDeclaration(name) ?? override
            else {
                collected.append(ValidationError(reason: "no element declaration for '\(name.localName)'", at: path))
                return nil
            }
            if override == nil, rootNamespaceMismatch(name) {
                collected.append(ValidationError(reason: "root element '\(name.localName)' is not in the schema target namespace '\(targetNamespace ?? "")'", at: path))
                return nil
            }
            if abstractElements.contains(name.localName) {
                collected.append(ValidationError(reason: "abstract element '\(name.localName)' must not appear in an instance", at: path))
                return nil
            }
            return declaration
        }

        /// The global element declaration for a qualified root name, mirroring the
        /// tree path's `globalElementDeclaration`: a namespaced lookup, with the bare
        /// `rootElements` map used only for a no-namespace root (never across
        /// namespaces, which would collide same-local-name globals).
        private func globalDeclaration(_ name: PureXML.Model.QualifiedName) -> PureXML.Schema.ElementType? {
            if let declaration = validator.types[PureXML.Schema.XSDParser.elementDeclarationKey(name)] {
                return declaration
            }
            if name.namespaceURI == nil || name.namespaceURI?.isEmpty == true {
                return rootElements[name.localName]
            }
            return nil
        }

        private func rootNamespaceMismatch(_ name: PureXML.Model.QualifiedName) -> Bool {
            guard let target = targetNamespace, !target.isEmpty, name.namespaceURI != target else { return false }
            return validator.types[PureXML.Schema.XSDParser.elementDeclarationKey(name)] == nil
        }

        /// The type an element's `xsi:type` names, resolved through its in-scope
        /// prefix bindings. Used where an element has no governing declaration but a
        /// concrete `xsi:type` supplies the type: an undeclared root (the tree path's
        /// `SchemaDocument` Sun target-namespace fallback) and a strict-wildcard child
        /// with no global declaration (the tree path's `xsiDeclaredType`).
        private func xsiTypeNamedType(_ element: PureXML.Model.Element, _ bindings: [String: String]) -> PureXML.Schema.ElementType? {
            guard PureXML.Schema.ComplexValidator.xsiTypeAttributeValue(element) != nil else { return nil }
            guard let reference = PureXML.Schema.ComplexValidator.xsiTypeReference(element, namespaceBindings: bindings),
                  let type = PureXML.Schema.ComplexValidator.resolveNamedType(reference, in: validator.types)
            else { return nil }
            return type
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
    /// In-scope prefix bindings at this element (ancestors merged with own `xmlns`),
    /// so a descendant's `xsi:type` resolves against prefixes declared up the tree.
    var bindings: [String: String] = [:]
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
