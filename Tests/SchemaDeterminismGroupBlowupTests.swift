import Testing
@testable import PureXML

/// The compositional UPA check (ContentModelDeterminism via CompositionalDeterminism)
/// summarizes each `<xs:group>` once, so a multiply-referenced nested group whose
/// inlined position count is `2^depth` is checked in polynomial time instead of being
/// silently skipped by the former `positionCap` (which capped at 4096 positions).
/// These pin both the bound (no hang) and the verdict on schemas the old engine
/// could not check. The `.timeLimit` trait is native-only (unsupported by the
/// single-threaded WASI runtime), and the depth is smaller on WASI (~30x slower);
/// both depths still exceed the old 4096-position cap, so the point holds.
@Suite("UPA on 2^K nested-group content models")
struct SchemaDeterminismGroupBlowupTests {
    // The compiled content model also memoizes group expansion
    // (GroupParticleMemo), so even these depths build in O(depth), not 2^depth: a
    // depth past ~25 is infeasible to inline at all, so it doubles as a regression
    // guard on that memo. WASI uses a smaller depth (~30x slower runtime).
    #if os(WASI)
        private static let depth = 16 // 2^16 = 65536 inlined positions, past the old 4096 cap
    #else
        private static let depth = 40 // 2^40 inlined positions: infeasible without memoization
    #endif

    /// `g0=(g1,g1) … g{depth-1}=(g{depth},g{depth})`, leaf `g{depth}` = the given model.
    /// Inlined this is `2^depth` positions; summarized it is `depth` groups.
    private func doublingSchema(leaf: String) -> String {
        let depth = Self.depth
        var parts = ["<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">"]
        for level in 0 ..< depth {
            parts.append("<xs:group name=\"g\(level)\"><xs:sequence>"
                + "<xs:group ref=\"g\(level + 1)\"/><xs:group ref=\"g\(level + 1)\"/>"
                + "</xs:sequence></xs:group>")
        }
        parts.append("<xs:group name=\"g\(depth)\"><xs:sequence>\(leaf)</xs:sequence></xs:group>")
        parts.append("<xs:complexType name=\"T\"><xs:sequence><xs:group ref=\"g0\"/></xs:sequence></xs:complexType>")
        parts.append("<xs:element name=\"doc\" type=\"T\"/>")
        parts.append("</xs:schema>")
        return parts.joined()
    }

    #if os(WASI)
        @Test("a deep deterministic nested-group model compiles (no hang, accepted)")
    #else
        @Test("a deep deterministic nested-group model compiles (no hang, accepted)", .timeLimit(.minutes(1)))
    #endif
    func test_deterministicBlowupCompiles() throws {
        // The leaf is a single element, so the model expands to many copies of `e` in
        // sequence: deterministic (each position is the same name, matched in order),
        // so the schema is valid. The old engine hit positionCap and skipped this.
        _ = try PureXML.Schema.Document(doublingSchema(leaf: "<xs:element name=\"e\"/>"))
    }

    #if os(WASI)
        @Test("a deep AMBIGUOUS nested-group model is rejected (not skipped)")
    #else
        @Test("a deep AMBIGUOUS nested-group model is rejected (not skipped)", .timeLimit(.minutes(1)))
    #endif
    func test_ambiguousBlowupRejected() {
        // The leaf is a choice of TWO distinct element declarations of the same name,
        // so the leaf group is itself ambiguous (a leading `e` could be either
        // particle). The compositional check finds the conflict even though the model
        // expands past the old cap; the old engine hit positionCap and silently
        // accepted it. (`(g, g)` of ONE group is NOT a conflict, since both references
        // share the same particle identity, matching the prior oracle.)
        let leaf = "<xs:choice><xs:element name=\"e\"/><xs:element name=\"e\"/></xs:choice>"
        #expect((try? PureXML.Schema.Document(doublingSchema(leaf: leaf))) == nil)
    }
}
