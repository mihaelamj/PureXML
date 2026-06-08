public extension PureXML.Schema {
    /// How a named complex type is derived from its base: the base type's local
    /// name and whether the derivation is an extension or a restriction. This is
    /// the backbone the `block`, `final`, and `xsi:type`-substitution checks walk
    /// to decide whether a derivation is permitted.
    struct TypeDerivation: Sendable, Equatable {
        /// The local name of the base type this type derives from.
        public var base: String
        /// Whether this type extends or restricts its base.
        public var method: DerivationMethod

        public init(base: String, method: DerivationMethod) {
            self.base = base
            self.method = method
        }
    }
}
