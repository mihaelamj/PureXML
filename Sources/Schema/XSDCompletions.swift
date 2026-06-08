public extension PureXML.Schema {
    /// What a schema allows at an element: the next child elements, whether the
    /// content may end here, and the declared attributes. For editor completions
    /// and "what's missing".
    struct Completions: Sendable, Equatable {
        /// Element names allowed as the next child at the current position, in
        /// content-model order. A content model with a wildcard (`xs:any`) leaves
        /// this empty and sets `allowsAnyElement`.
        public var elements: [String]
        /// Whether the content may legally end here. When false, a required child
        /// is still expected.
        public var complete: Bool
        /// Whether a wildcard permits arbitrary further elements here.
        public var allowsAnyElement: Bool
        /// The declared attributes, each with whether it is required and already
        /// present on the element.
        public var attributes: [AttributeCompletion]

        public init(elements: [String], complete: Bool, allowsAnyElement: Bool, attributes: [AttributeCompletion]) {
            self.elements = elements
            self.complete = complete
            self.allowsAnyElement = allowsAnyElement
            self.attributes = attributes
        }
    }

    /// One declared attribute in a ``Completions``.
    struct AttributeCompletion: Sendable, Equatable {
        public var name: String
        public var required: Bool
        public var present: Bool

        public init(name: String, required: Bool, present: Bool) {
            self.name = name
            self.required = required
            self.present = present
        }
    }

    /// Computes ``Completions`` from the compiled schema: the follow-set of a
    /// content model and the resolution of an element's declared type along a
    /// coding path.
    enum CompletionEngine {
        /// The completions for `element` given its declared `type`, resolving
        /// references through `types`.
        static func completions(for element: PureXML.Model.Element, type: ElementType, types: [String: ElementType]) -> Completions {
            guard case let .complex(complex) = resolve(type, types: types) else {
                return Completions(elements: [], complete: true, allowsAnyElement: false, attributes: [])
            }
            let present = Set(element.attributes.map(\.name.localName))
            let attributes = complex.attributes.map {
                AttributeCompletion(name: $0.name.localName, required: $0.required, present: present.contains($0.name.localName))
            }
            let childNames = element.children.compactMap { child -> PureXML.Model.QualifiedName? in
                if case let .element(inner) = child { return inner.name }
                return nil
            }
            switch complex.content {
            case let .elementOnly(particle), let .mixed(particle):
                let (labels, complete) = ContentNFABuilder.build(particle).follow(after: childNames)
                let names = labels.compactMap { if case let .name(name) = $0 { name.description } else { nil } }
                let anyElement = labels.contains { if case .any = $0 { true } else { false } }
                return Completions(elements: names, complete: complete, allowsAnyElement: anyElement, attributes: attributes)
            case .empty, .simpleContent:
                return Completions(elements: [], complete: true, allowsAnyElement: false, attributes: attributes)
            }
        }

        /// Resolves the declared type of the element a coding path addresses, by
        /// walking the global declaration then each parent's content model.
        static func elementType(
            at path: [PureXML.Validation.PathKey],
            elements: [String: ElementType],
            types: [String: ElementType],
        ) -> ElementType? {
            guard let first = path.first, var current = elements[first.stringValue] else { return nil }
            for step in path.dropFirst() {
                guard case let .complex(complex) = resolve(current, types: types),
                      let childType = childTypes(of: complex)[step.stringValue]
                else {
                    return nil
                }
                current = childType
            }
            return current
        }

        /// Resolves an `ElementType` to its underlying simple or complex type,
        /// following named references.
        static func resolve(_ type: ElementType, types: [String: ElementType]) -> ElementType {
            var current = type
            var guardCount = 0
            while case let .typeReference(name) = current, let next = types[name], guardCount < types.count + 1 {
                current = next
                guardCount += 1
            }
            return current
        }

        /// The child element declarations of a complex type's content model, keyed
        /// by the qualified-name description used in coding paths.
        private static func childTypes(of complex: ComplexType) -> [String: ElementType] {
            switch complex.content {
            case let .elementOnly(particle), let .mixed(particle):
                var result: [String: ElementType] = [:]
                collect(particle.term, into: &result)
                return result
            case .empty, .simpleContent:
                return [:]
            }
        }

        private static func collect(_ term: Term, into result: inout [String: ElementType]) {
            switch term {
            case let .element(name, type):
                if let type { result[name.description] = type }
            case let .group(group):
                for member in group.particles {
                    collect(member.term, into: &result)
                }
            case .wildcard:
                break
            }
        }
    }
}
