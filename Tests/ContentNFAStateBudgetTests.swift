@testable import PureXML
import Testing

/// Guards the content-model NFA builder against occurrence-explosion (#129).
/// The per-particle unroll cap bounds one repetition, but nested high-`maxOccurs`
/// particles multiply: the XSTS msMeta Particles set drove the builder to 8 GB
/// and OOM-killed the suite. A total state ceiling caps the whole automaton,
/// degrading further repetition to star. This locks that ceiling in: the
/// pathological model must build, stay bounded, and still match without
/// crashing, while ordinary models are untouched.
@Suite("Content NFA state budget")
struct ContentNFAStateBudgetTests {
    private func element(_ name: String, min: Int, max: Int?) -> PureXML.Schema.Particle {
        .init(minOccurs: min, maxOccurs: max, term: .element(name: .init(name), type: nil))
    }

    /// A sequence repeated `min` times, each repeat holding an element repeated
    /// `min` times: naively `min * min` automaton states.
    private func nested(min: Int) -> PureXML.Schema.Particle {
        let inner = element("a", min: min, max: min)
        return .init(
            minOccurs: min,
            maxOccurs: min,
            term: .group(.init(compositor: .sequence, particles: [inner])),
        )
    }

    @Test("A nested occurrence explosion stays bounded instead of exhausting memory")
    func test_nestedExplosionBounded() {
        // 16384 * 16384 ~ 2.7e8 states without a total cap; the ceiling is 2^20.
        let nfa = PureXML.Schema.ContentNFABuilder.build(nested(min: 16384))
        // Bounded to the ceiling plus at most one in-flight term expansion,
        // far below the naive product that previously allocated until death.
        #expect(nfa.states.count < 1_500_000)
        // The degraded automaton must still answer queries without crashing.
        let names = Array(repeating: PureXML.Model.QualifiedName("a"), count: 32)
        _ = nfa.matchesWhole(names)
    }

    @Test("Ordinary content models are unaffected by the ceiling")
    func test_ordinaryModelUnchanged() {
        let particle = PureXML.Schema.Particle(
            minOccurs: 1,
            maxOccurs: nil,
            term: .group(.init(compositor: .sequence, particles: [element("a", min: 1, max: 1)])),
        )
        let nfa = PureXML.Schema.ContentNFABuilder.build(particle)
        #expect(nfa.states.count < 64)
        #expect(nfa.matchesWhole([.init("a"), .init("a"), .init("a")]))
        #expect(!nfa.matchesWhole([.init("b")]))
    }
}
