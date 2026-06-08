public extension PureXML.Schema {
    /// A RELAX NG name class: which element or attribute names a pattern matches.
    indirect enum NameClass: Sendable {
        case anyName
        case anyNameExcept(NameClass)
        case name(namespace: String, localName: String)
        case nsName(String)
        case nsNameExcept(namespace: String, except: NameClass)
        case choice(NameClass, NameClass)

        /// Whether `name` is in this class.
        func contains(_ name: PureXML.Model.QualifiedName) -> Bool {
            let namespace = name.namespaceURI ?? ""
            switch self {
            case .anyName: return true
            case let .anyNameExcept(except): return !except.contains(name)
            case let .name(wantedNamespace, wantedLocal): return namespace == wantedNamespace && name.localName == wantedLocal
            case let .nsName(wantedNamespace): return namespace == wantedNamespace
            case let .nsNameExcept(wantedNamespace, except): return namespace == wantedNamespace && !except.contains(name)
            case let .choice(left, right): return left.contains(name) || right.contains(name)
            }
        }
    }

    /// A RELAX NG pattern (the simplified algebra used by the derivative
    /// algorithm). `optional`, `zeroOrMore`, and `mixed` are expressed through
    /// these constructors; `after` is internal to derivation.
    indirect enum Pattern: Sendable {
        case empty
        case notAllowed
        case text
        case choice(Pattern, Pattern)
        case interleave(Pattern, Pattern)
        case group(Pattern, Pattern)
        case oneOrMore(Pattern)
        case element(NameClass, Pattern)
        case attribute(NameClass, Pattern)
        case data(SimpleType)
        case value(String)
        case list(Pattern)
        case ref(String)
        case after(Pattern, Pattern)
    }
}
