private typealias XSDNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// Compiles several schema documents that jointly form one schema (a
    /// multi-document `schemaTest`, or any set assembled outside the
    /// `import`/`include` graph) as a single union: their container closures are
    /// pooled into one context so cross-document facts (substitution-group
    /// membership above all) are global, exactly as if one document imported the
    /// rest. Merging separately compiled `Document`s cannot do this, since each
    /// document's content models are already frozen with only the substitution
    /// members visible in its own closure (#161).
    ///
    /// A document supplied directly and also reachable through another's `import`
    /// is pooled once (deduplicated by target namespace and the set of its
    /// top-level component names). The document with the largest closure, i.e. the
    /// one that imports the others, is the primary, matching the result of
    /// compiling that document alone.
    static func parse(union sources: [String], loader: (String) -> String? = { _ in nil }) throws -> PureXML.Schema.XSDCompiled {
        var parsed: [(schema: XSDTree, tuples: [(location: String?, tree: XSDTree)])] = []
        for source in sources {
            var visited: Set<String> = []
            guard let root = try? PureXML.parseTree(source),
                  let schema = XSDNode.elementChildren(root).first(where: { XSDNode.localName($0) == "schema" })
            else { continue }
            parsed.append((schema, XSDNode.collectContainers(schema, loader, &visited)))
        }
        guard !parsed.isEmpty else { throw PureXML.Schema.SchemaError.notASchema }
        // The widest closure is the importing document; compile as if it were the
        // single entry point so the primary target namespace matches. Tie-break by
        // target namespace so the choice is deterministic for independent roots.
        parsed.sort {
            $0.tuples.count != $1.tuples.count
                ? $0.tuples.count > $1.tuples.count
                : (XSDNode.attribute($0.schema, "targetNamespace") ?? "") < (XSDNode.attribute($1.schema, "targetNamespace") ?? "")
        }
        guard let schema = parsed.first?.schema else { throw PureXML.Schema.SchemaError.notASchema }

        var seenSignatures: Set<String> = []
        var containerTuples: [(location: String?, tree: XSDTree)] = []
        for tuple in parsed.flatMap(\.tuples) {
            if let signature = unionDedupSignature(tuple.tree) {
                guard seenSignatures.insert(signature).inserted else { continue }
            }
            containerTuples.append(tuple)
        }

        let containers = containerTuples.map(\.tree)
        let derivation = derivationTables(containers)
        let containerLocations = containerLocationMap(containerTuples, rootLocation: nil)
        let compositionLoaded = XSDNode.compositionLoaded(from: containerTuples)
        var context = createContext(
            schema: schema,
            containers: containers,
            derivation: derivation,
            containerLocations: containerLocations,
            compositionLoaded: compositionLoaded,
        )
        return finishCompile(schema: schema, containers: containers, derivation: derivation, context: &context)
    }

    /// A dedup key for a schema container in a union: its target namespace plus its
    /// sorted top-level component names. The same document parsed twice (as a
    /// direct source and through another's `import`) collapses to one. Only
    /// namespaced `schema` containers are keyed; chameleon (no-namespace) includes
    /// and `redefine` wrappers are parent-specific and always kept.
    private static func unionDedupSignature(_ tree: XSDTree) -> String? {
        guard XSDNode.localName(tree) == "schema" else { return nil }
        guard let namespace = XSDNode.attribute(tree, "targetNamespace"), !namespace.isEmpty else { return nil }
        let components = XSDNode.elementChildren(tree)
            .map { "\(XSDNode.localName($0)):\(XSDNode.attribute($0, "name") ?? "")" }
            .sorted()
        return "\(namespace)\u{1}\(components.joined(separator: "\u{1}"))"
    }
}
