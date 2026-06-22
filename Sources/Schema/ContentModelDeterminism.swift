public extension PureXML.Schema {
    /// Unique Particle Attribution (cos-nonambig, XSD 1.0 3.8.6): a content model
    /// must be deterministic, so each element in an instance is attributed to one
    /// particle without lookahead. The model is ambiguous iff some decision set (the
    /// content's `first`, or any item's `followpos`) holds two distinct particles
    /// whose labels can match the same element.
    ///
    /// The check delegates to ``PureXML/Schema/CompositionalDeterminism``, which
    /// computes `first`/`followlast` over PARTICLE identities WITHOUT inlining
    /// `<xs:group ref>`, so a multiply-referenced nested group cannot blow up to
    /// `2^K` positions. That gives a proven `O(nodes * particles^2)` bound with no
    /// position cap and no silent skip (production-readiness stopper #4). The
    /// compositional engine was proven verdict-equivalent to the prior inlining
    /// Glushkov automaton by a differential over the whole XSTS corpus (zero
    /// divergences) before it became authoritative; see
    /// docs/design/counted-content-automaton.md.
    ///
    /// It works on a LITERAL view of the raw schema tree, distinct from the compiled
    /// (instance) content model: a `ref` is one particle carrying its resolved QName
    /// (prefix bindings, not the blanket target namespace), and substitution groups
    /// are NOT expanded. The overlap test is QName-only, so it can only under-report
    /// substitution-group ambiguities, never over-report.
    enum ContentModelDeterminism {
        /// Every UPA-violation finding across the schema's complex-type content
        /// models, deduplicated by message in first-seen order. Each finding is
        /// located on the content-model node (`sequence`/`choice`/`all`/`group`)
        /// whose particles are ambiguous; a message shared by two models locates on
        /// the first, preserving the deduplicated count.
        static func violationFindings(in schema: XSDTree, context: XSDContext) -> [PureXML.Schema.SchemaLocatedFinding] {
            let bindings = namespaceBindings(schema)
            var findings: [PureXML.Schema.SchemaLocatedFinding] = []
            var seen: Set<String> = []
            forEachComplexType(schema) { complexType in
                let models = effectiveModelNodes(complexType, bindings, context, [])
                guard !models.isEmpty,
                      let conflict = PureXML.Schema.CompositionalDeterminism.violation(models, bindings, context)
                else { return }
                // The conflicting particle the author can act on is in this type's own
                // content, so locate on its own content-model node.
                let node = contentModelNode(complexType) ?? complexType
                if seen.insert(conflict).inserted {
                    findings.append(PureXML.Schema.SchemaLocatedFinding(reason: conflict, node: node))
                }
            }
            return findings
        }

        /// The prefix-to-namespace bindings declared on the schema element (its
        /// `xmlns:prefix` attributes; the default namespace under the empty key).
        private static func namespaceBindings(_ schema: XSDTree) -> [String: String] {
            var bindings: [String: String] = [:]
            for attribute in schema.attributes {
                if attribute.name.prefix == "xmlns" {
                    bindings[attribute.name.localName] = attribute.value
                } else if attribute.name.prefix == nil, attribute.name.localName == "xmlns" {
                    bindings[""] = attribute.value
                }
            }
            return bindings
        }

        /// Visits every `complexType` element in the schema document, skipping
        /// foreign annotation content.
        private static func forEachComplexType(_ node: XSDTree, _ visit: (XSDTree) -> Void) {
            let local = PureXML.Schema.XSDNode.localName(node)
            if local == "appinfo" || local == "documentation" { return }
            if local == "complexType" { visit(node) }
            for child in PureXML.Schema.XSDNode.elementChildren(node) {
                forEachComplexType(child, visit)
            }
        }
    }
}
