public extension PureXML.Schema {
    /// A way one type is derived from another, or one element substitutes for
    /// another: by extension, by restriction, or (for elements) by substitution
    /// group membership. Used by the `block` and `final` derivation controls.
    enum DerivationMethod: Sendable, Equatable, Hashable {
        case `extension`
        case restriction
        case substitution
    }
}
