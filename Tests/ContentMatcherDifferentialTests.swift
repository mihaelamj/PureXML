@testable import PureXML
import Testing

/// Locks the two content-model matchers together (#115): the DTD matcher
/// (positional set closure) and the XSD matcher (Thompson NFA) solve the same
/// problem with different algorithms, so equivalent models must agree on every
/// child sequence.
@Suite("DTD vs XSD content-matcher differential")
struct ContentMatcherDifferentialTests {
    private struct ModelCase {
        let dtdModel: String
        let xsdParticle: PureXML.Schema.Particle
        let sequences: [(names: [String], valid: Bool)]
    }

    private func element(_ name: String, min: Int = 1, max: Int? = 1) -> PureXML.Schema.Particle {
        .init(minOccurs: min, maxOccurs: max, term: .element(name: .init(name), type: nil, typeName: nil))
    }

    private func group(_ compositor: PureXML.Schema.Compositor, _ particles: [PureXML.Schema.Particle], min: Int = 1, max: Int? = 1) -> PureXML.Schema.Particle {
        .init(minOccurs: min, maxOccurs: max, term: .group(.init(compositor: compositor, particles: particles)))
    }

    private var cases: [ModelCase] {
        [
            ModelCase(
                dtdModel: "(a,b)",
                xsdParticle: group(.sequence, [element("a"), element("b")]),
                sequences: [(["a", "b"], true), (["b", "a"], false), (["a"], false), ([], false)],
            ),
            ModelCase(
                dtdModel: "(a|b)",
                xsdParticle: group(.choice, [element("a"), element("b")]),
                sequences: [(["a"], true), (["b"], true), (["a", "b"], false), ([], false)],
            ),
            ModelCase(
                dtdModel: "(a)*",
                xsdParticle: group(.sequence, [element("a")], min: 0, max: nil),
                sequences: [([], true), (["a"], true), (["a", "a", "a"], true), (["b"], false)],
            ),
            ModelCase(
                dtdModel: "(a)+",
                xsdParticle: group(.sequence, [element("a")], min: 1, max: nil),
                sequences: [([], false), (["a"], true), (["a", "a"], true)],
            ),
            ModelCase(
                dtdModel: "(a)?",
                xsdParticle: group(.sequence, [element("a")], min: 0, max: 1),
                sequences: [([], true), (["a"], true), (["a", "a"], false)],
            ),
            ModelCase(
                dtdModel: "((a,b)|c)",
                xsdParticle: group(.choice, [group(.sequence, [element("a"), element("b")]), element("c")]),
                sequences: [(["a", "b"], true), (["c"], true), (["a", "c"], false), (["a", "b", "c"], false)],
            ),
        ]
    }

    @Test("Equivalent DTD and XSD content models agree on every child sequence")
    func test_matchersAgree() {
        for modelCase in cases {
            guard case let .children(particle) = PureXML.Validation.ContentModelParser.parse(modelCase.dtdModel) else {
                Issue.record("DTD model '\(modelCase.dtdModel)' did not parse to element content")
                continue
            }
            let nfa = PureXML.Schema.ContentNFABuilder.build(modelCase.xsdParticle)
            for sequence in modelCase.sequences {
                let dtd = PureXML.Validation.ContentModelMatcher.matchesChildren(particle, sequence.names)
                let xsd = nfa.matchesWhole(sequence.names.map { PureXML.Model.QualifiedName($0) })
                #expect(dtd == sequence.valid, "DTD '\(modelCase.dtdModel)' wrong for \(sequence.names)")
                #expect(xsd == sequence.valid, "XSD '\(modelCase.dtdModel)' wrong for \(sequence.names)")
                #expect(dtd == xsd, "matchers disagree on '\(modelCase.dtdModel)' for \(sequence.names)")
            }
        }
    }
}
