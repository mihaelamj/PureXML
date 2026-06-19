import Testing
@testable import PureXML

/// Guards the counted content-model automaton against occurrence explosion (#129).
/// Occurrence bounds must affect counters, not program size, and finite bounds
/// must stay exact instead of widening to `*`.
@Suite("Counted content automaton")
struct ContentNFAStateBudgetTests {
    private typealias Schema = PureXML.Schema
    private typealias Name = PureXML.Model.QualifiedName

    private func decimal(_ value: String) throws -> Schema.NonNegativeDecimal {
        try #require(Schema.NonNegativeDecimal(lexical: value))
    }

    private func element(_ name: String, min: Int = 1, max: Int? = 1) -> Schema.Particle {
        .init(minOccurs: min, maxOccurs: max, term: .element(name: .init(name), type: nil, typeName: nil))
    }

    private func element(_ name: String, range: Schema.OccurrenceRange) -> Schema.Particle {
        .init(occurrenceRange: range, term: .element(name: .init(name), type: nil, typeName: nil))
    }

    private func group(_ compositor: Schema.Compositor, _ particles: [Schema.Particle], min: Int = 1, max: Int? = 1) -> Schema.Particle {
        .init(minOccurs: min, maxOccurs: max, term: .group(.init(compositor: compositor, particles: particles)))
    }

    private func names(_ values: String...) -> [Name] {
        values.map(Name.init)
    }

    @Test("Finite exact occurrence rejects too few and too many children")
    func test_exactFiniteOccurrence() {
        let nfa = Schema.ContentNFABuilder.build(element("a", min: 2, max: 2))
        #expect(!nfa.matchesWhole(names("a")))
        #expect(nfa.matchesWhole(names("a", "a")))
        #expect(!nfa.matchesWhole(names("a", "a", "a")))
    }

    @Test("Finite optional tail does not widen to star")
    func test_finiteOptionalTailDoesNotWiden() {
        let nfa = Schema.ContentNFABuilder.build(element("a", min: 0, max: 2))
        #expect(nfa.matchesWhole([]))
        #expect(nfa.matchesWhole(names("a")))
        #expect(nfa.matchesWhole(names("a", "a")))
        #expect(!nfa.matchesWhole(names("a", "a", "a")))
    }

    @Test("Huge finite upper bound stays exact without proportional states")
    func test_hugeFiniteUpperBound() throws {
        let huge = try decimal("100000000000000000000")
        let particle = element(
            "a",
            range: .init(minimum: .init(2), maximum: .finite(huge)),
        )
        let nfa = Schema.ContentNFABuilder.build(particle)
        #expect(nfa.states.count < 16)
        #expect(!nfa.matchesWhole(names("a")))
        #expect(nfa.matchesWhole(names("a", "a")))
        #expect(nfa.matchesWhole(names("a", "a", "a", "a")))
    }

    @Test("Nested finite occurrences compose exactly")
    func test_nestedFiniteOccurrences() {
        let inner = element("a", min: 2, max: 3)
        let outer = group(.sequence, [inner], min: 2, max: 2)
        let nfa = Schema.ContentNFABuilder.build(outer)
        #expect(!nfa.matchesWhole(names("a", "a", "a")))
        #expect(nfa.matchesWhole(names("a", "a", "a", "a")))
        #expect(nfa.matchesWhole(names("a", "a", "a", "a", "a")))
        #expect(nfa.matchesWhole(names("a", "a", "a", "a", "a", "a")))
        #expect(!nfa.matchesWhole(names("a", "a", "a", "a", "a", "a", "a")))
    }

    @Test("A huge required prefix does not offer the following particle early")
    func test_hugeMinimumFollowSet() throws {
        let huge = try decimal("1000000000000")
        let requiredA = element(
            "a",
            range: .init(minimum: huge, maximum: .finite(huge)),
        )
        let particle = group(.sequence, [requiredA, element("b")])
        let nfa = Schema.ContentNFABuilder.build(particle)

        let follow = nfa.follow(after: names("a", "a"))
        let allowedNames = follow.allowed.compactMap { label -> String? in
            if case let .name(name) = label { return name.localName }
            return nil
        }

        #expect(Set(allowedNames) == ["a"])
        #expect(!follow.complete)
    }

    @Test("A nested occurrence explosion stays structurally bounded")
    func test_nestedExplosionBounded() {
        let inner = element("a", min: 16384, max: 16384)
        let nested = group(.sequence, [inner], min: 16384, max: 16384)
        let nfa = Schema.ContentNFABuilder.build(nested)
        #expect(nfa.states.count < 32)
        #expect(!nfa.matchesWhole(Array(repeating: Name("a"), count: 32)))
    }
}
