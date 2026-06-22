extension PureXML.Schema {
    /// The key under which an `<xs:group>` reference's expansion is memoized: the
    /// group DEFINITION node and the cycle-visiting set at the reference site. The
    /// expansion is determined by these (the namespace scope is fixed per
    /// definition), so two references that share them share the result.
    struct GroupParticleMemoKey: Hashable {
        let definition: ObjectIdentifier
        let visiting: Set<String>
    }

    /// Memoizes group-reference expansion during one schema compile. A
    /// multiply-referenced nested group (`g0=(g1,g1), g1=(g2,g2), …`) otherwise
    /// rebuilds each subtree per reference, an exponential `2^K` compile; sharing the
    /// expansion across sibling references drops the build to `O(groups)`. The
    /// resulting `Particle` is semantically identical (a value type, so the shared
    /// content term is copy-on-write), only built once. A reference type so it is
    /// shared across the value copies `XSDContext.scoped`/`visiting` make; one
    /// instance per compile.
    final class GroupParticleMemo {
        var store: [GroupParticleMemoKey: PureXML.Schema.Particle] = [:]
    }
}
