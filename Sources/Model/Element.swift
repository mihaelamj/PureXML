public extension PureXML.Model {
    /// An XML element: a qualified name, ordered attributes, and ordered child nodes.
    ///
    /// A value type with full value semantics: copying an element copies its
    /// children (lazily, copy-on-write). The children are held behind a reference
    /// (``ElementStorage``) so a deeply-nested tree neither overflows the stack on
    /// release nor on equality and hashing, which walk the tree iteratively.
    struct Element: Sendable {
        public var name: QualifiedName
        public var attributes: [Attribute]
        /// Copy-on-write backing; `children` is the public, value-semantic view.
        var storage: ElementStorage

        /// The element's child nodes. Reads share the backing storage; a write
        /// first copies the storage if it is shared, preserving value semantics.
        ///
        /// The `_modify` accessor yields the backing array in place (after the
        /// copy-on-write check), so an in-place mutation such as
        /// `element.children.append(_:)` does not copy the whole array on every
        /// call. Without it a computed property would read, mutate a temporary,
        /// and write back, making repeated appends quadratic (which is exactly the
        /// pattern the parser uses while building an element).
        public var children: [Node] {
            get { storage.children }
            _modify {
                if !isKnownUniquelyReferenced(&storage) {
                    storage = ElementStorage(storage.children)
                }
                yield &storage.children
            }
            set {
                if isKnownUniquelyReferenced(&storage) {
                    storage.children = newValue
                } else {
                    storage = ElementStorage(newValue)
                }
            }
        }

        public init(
            name: QualifiedName,
            attributes: [Attribute] = [],
            children: [Node] = [],
        ) {
            self.name = name
            self.attributes = attributes
            storage = ElementStorage(children)
        }

        public init(
            _ name: String,
            attributes: [Attribute] = [],
            children: [Node] = [],
        ) {
            self.init(
                name: QualifiedName(name),
                attributes: attributes,
                children: children,
            )
        }

        /// The concatenated text of direct text and CDATA children.
        public var text: String {
            children.reduce(into: "") { accumulated, child in
                switch child {
                case let .text(value), let .cdata(value):
                    accumulated += value
                default:
                    break
                }
            }
        }
    }
}

extension PureXML.Model.Element: Equatable, Hashable {
    /// Value equality over the whole subtree, compared iteratively (see
    /// ``PureXML/Model/Node`` `==`) so a deeply-nested element does not recurse.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        PureXML.Model.Node.treesEqual(.element(lhs), .element(rhs))
    }

    /// Hashes the whole subtree iteratively, consistent with `==`.
    public func hash(into hasher: inout Hasher) {
        PureXML.Model.Node.element(self).hash(into: &hasher)
    }
}
