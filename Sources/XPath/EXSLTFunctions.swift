extension PureXML.XPath {
    /// The EXSLT extension functions (http://exslt.org/...), dispatched by the
    /// namespace a function's prefix resolves to: the `math`, `sets`, and the
    /// `common` modules. Registered through ``FunctionTable`` so they are
    /// available wherever a prefix is bound to an EXSLT namespace.
    enum EXSLT {
        static let common = "http://exslt.org/common"
        static let math = "http://exslt.org/math"
        static let sets = "http://exslt.org/sets"

        /// The implementation for an EXSLT `local` name in namespace `uri`, or nil.
        static func implementation(uri: String, local: String) -> FunctionImplementation? {
            switch uri {
            case math: mathFunction(local)
            case sets: setsFunction(local)
            case common: commonFunction(local)
            default: nil
            }
        }

        // MARK: common

        private static func commonFunction(_ local: String) -> FunctionImplementation? {
            guard local == "object-type" else { return nil }
            return { arguments, _ in
                switch arguments.first {
                case .nodeSet: .string("node-set")
                case .boolean: .string("boolean")
                case .number: .string("number")
                case .string, .none: .string("string")
                }
            }
        }

        // MARK: math

        private static func mathFunction(_ local: String) -> FunctionImplementation? {
            switch local {
            case "min": { arguments, _ in .number(extremum(arguments.first, isMin: true)) }
            case "max": { arguments, _ in .number(extremum(arguments.first, isMin: false)) }
            case "highest": { arguments, _ in .nodeSet(extremeNodes(arguments.first, isMin: false)) }
            case "lowest": { arguments, _ in .nodeSet(extremeNodes(arguments.first, isMin: true)) }
            case "abs": { arguments, _ in .number(abs(arguments.first?.number ?? .nan)) }
            case "sqrt": { arguments, _ in .number((arguments.first?.number ?? .nan).squareRoot()) }
            default: nil
            }
        }

        /// The minimum or maximum of a node-set's numeric values; NaN for an empty
        /// set or any non-numeric node (the EXSLT rule).
        private static func extremum(_ value: Value?, isMin: Bool) -> Double {
            guard let nodes = value?.nodes, !nodes.isEmpty else { return .nan }
            let numbers = nodes.map { PureXML.XPath.Value.parseNumber($0.stringValue) }
            if numbers.contains(where: \.isNaN) { return .nan }
            return isMin ? numbers.min() ?? .nan : numbers.max() ?? .nan
        }

        /// The nodes whose numeric value equals the set's maximum (or minimum),
        /// in document order; empty when any value is NaN.
        private static func extremeNodes(_ value: Value?, isMin: Bool) -> [Node] {
            guard let nodes = value?.nodes, !nodes.isEmpty else { return [] }
            let target = extremum(value, isMin: isMin)
            guard !target.isNaN else { return [] }
            return nodes
                .filter { PureXML.XPath.Value.parseNumber($0.stringValue) == target }
                .sortedByDocumentOrder()
        }

        // MARK: sets

        private static func setsFunction(_ local: String) -> FunctionImplementation? {
            switch local {
            case "distinct": { arguments, _ in .nodeSet(distinct(arguments.first)) }
            case "difference": { arguments, _ in .nodeSet(difference(arguments)) }
            case "intersection": { arguments, _ in .nodeSet(intersection(arguments)) }
            case "has-same-node": { arguments, _ in .boolean(hasSameNode(arguments)) }
            case "leading": { arguments, _ in .nodeSet(relative(arguments, leading: true)) }
            case "trailing": { arguments, _ in .nodeSet(relative(arguments, leading: false)) }
            default: nil
            }
        }

        private static func distinct(_ value: Value?) -> [Node] {
            guard let nodes = value?.nodes else { return [] }
            var seen: Set<String> = []
            var result: [Node] = []
            for node in nodes.sortedByDocumentOrder() where seen.insert(node.stringValue).inserted {
                result.append(node)
            }
            return result
        }

        private static func difference(_ arguments: [Value]) -> [Node] {
            let first = arguments.first?.nodes ?? []
            let second = Set(arguments.count > 1 ? arguments[1].nodes ?? [] : [])
            return first.filter { !second.contains($0) }.sortedByDocumentOrder()
        }

        private static func intersection(_ arguments: [Value]) -> [Node] {
            let first = arguments.first?.nodes ?? []
            let second = Set(arguments.count > 1 ? arguments[1].nodes ?? [] : [])
            return first.filter { second.contains($0) }.sortedByDocumentOrder()
        }

        private static func hasSameNode(_ arguments: [Value]) -> Bool {
            let second = Set(arguments.count > 1 ? arguments[1].nodes ?? [] : [])
            return (arguments.first?.nodes ?? []).contains { second.contains($0) }
        }

        /// `set:leading` / `set:trailing`: the nodes of the first set that precede
        /// (or follow) the first node, in document order, of the second set.
        private static func relative(_ arguments: [Value], leading: Bool) -> [Node] {
            let first = arguments.first?.nodes ?? []
            guard let pivot = (arguments.count > 1 ? arguments[1].nodes ?? [] : []).firstInDocumentOrder() else {
                return []
            }
            // Decorate once through a shared sibling-index cache: each node's
            // order key is computed a single time, and the per-parent index is
            // built once rather than rescanned for every node (which made this
            // quadratic over a wide fan-out).
            let cache = PureXML.XPath.SiblingIndexCache()
            let pivotKey = pivot.documentOrder(cache: cache)
            return first
                .map { (node: $0, key: $0.documentOrder(cache: cache)) }
                .filter { leading ? Node.ordered($0.key, before: pivotKey) : Node.ordered(pivotKey, before: $0.key) }
                .sorted { Node.ordered($0.key, before: $1.key) }
                .map(\.node)
        }
    }
}
