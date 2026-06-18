import Foundation
import Testing
@testable import PureXML

/// Reproducible xorshift64* generator: a seed that triggers a crash or hang
/// reproduces the exact input, so a fuzz failure is debuggable rather than a
/// one-off. Deterministic by construction (no system entropy).
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }
}

/// Builds structurally varied XSD schemas and XML instances to exercise the
/// schema compiler and validator across the input space, not just curated cases.
/// It deliberately reaches the hang/crash-prone shapes: deep nesting, large and
/// inverted occurrences, pointless (`maxOccurs="0"`) particles, wildcards,
/// element/group references and reference cycles, substitution-group chains,
/// `simpleType` restriction cycles, `complexContent` restrictions (the particle
/// restriction core), and pathological regex patterns.
private struct SchemaGenerator {
    var rng: SeededRNG

    private static let names = ["a", "b", "c", "head", "m1", "m2", "root"]
    private static let leafTypes = ["xs:string", "xs:integer", "xs:int", "xs:decimal", "xs:boolean", "B", "R", "s0", "s1"]
    private static let compositors = ["sequence", "choice", "all"]
    private static let patterns = ["a*", "(a+)+", "[a-", "a{2,1}", #"\p{L}+"#, "(.*)*", "", ".{0,9}"]

    private mutating func pick<Element>(_ options: [Element]) -> Element {
        options[Int.random(in: 0 ..< options.count, using: &rng)]
    }

    private mutating func toss() -> Bool {
        Bool.random(using: &rng)
    }

    /// A random occurrence attribute fragment, including the degenerate and
    /// illegal shapes (zero, unbounded, large, and inverted min > max).
    private mutating func occurrence() -> String {
        switch Int.random(in: 0 ..< 8, using: &rng) {
        case 0: ""
        case 1: " minOccurs=\"0\""
        case 2: " minOccurs=\"0\" maxOccurs=\"unbounded\""
        case 3: " maxOccurs=\"\(Int.random(in: 0 ... 5, using: &rng))\""
        case 4: " minOccurs=\"\(Int.random(in: 0 ... 4, using: &rng))\" maxOccurs=\"\(Int.random(in: 0 ... 6, using: &rng))\""
        case 5: " maxOccurs=\"0\""
        case 6: " minOccurs=\"5\" maxOccurs=\"2\""
        default: " maxOccurs=\"\(pick([10, 250, 1000]))\""
        }
    }

    private mutating func leaf() -> String {
        switch Int.random(in: 0 ..< 5, using: &rng) {
        case 0: "<xs:element name=\"\(pick(Self.names))\" type=\"\(pick(Self.leafTypes))\"\(occurrence())/>"
        case 1: "<xs:any\(occurrence()) processContents=\"\(pick(["strict", "lax", "skip"]))\"/>"
        case 2: "<xs:element ref=\"\(pick(Self.names))\"\(occurrence())/>"
        case 3: "<xs:group ref=\"\(pick(["g0", "g1"]))\"\(occurrence())/>"
        default: "<xs:element name=\"\(pick(Self.names))\"\(occurrence())/>"
        }
    }

    private mutating func particle(_ depth: Int) -> String {
        if depth <= 0 || toss() {
            return leaf()
        }
        let compositor = pick(Self.compositors)
        let children = (0 ..< Int.random(in: 0 ... 3, using: &rng)).map { _ in particle(depth - 1) }.joined()
        return "<xs:\(compositor)\(occurrence())>\(children)</xs:\(compositor)>"
    }

    private mutating func modelGroup(_ depth: Int) -> String {
        let compositor = pick(Self.compositors)
        let children = (0 ..< Int.random(in: 0 ... 4, using: &rng)).map { _ in particle(depth - 1) }.joined()
        return "<xs:\(compositor)>\(children)</xs:\(compositor)>"
    }

    mutating func schema() -> String {
        let qualified = toss()
        let header = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""
            + (qualified ? " targetNamespace=\"urn:t\" xmlns:t=\"urn:t\" elementFormDefault=\"qualified\"" : "")
            + ">"
        var parts = [header]
        // Named groups that may reference each other (g0 <-> g1 cycle exercises the
        // visiting-group guard).
        parts.append("<xs:group name=\"g0\">\(modelGroup(2))</xs:group>")
        parts.append("<xs:group name=\"g1\">\(modelGroup(2))</xs:group>")
        // Global elements with a substitution chain (m2 -> m1 -> head).
        parts.append("<xs:element name=\"head\" type=\"\(pick(Self.leafTypes))\"/>")
        parts.append("<xs:element name=\"m1\" substitutionGroup=\"head\"/>")
        parts.append("<xs:element name=\"m2\" substitutionGroup=\"m1\"/>")
        // simpleType restriction cycle (s0 <-> s1) plus facets and a pattern.
        parts.append("<xs:simpleType name=\"s0\"><xs:restriction base=\"\(pick(["xs:string", "s1"]))\">"
            + "<xs:maxLength value=\"\(Int.random(in: 0 ... 9, using: &rng))\"/><xs:pattern value=\"\(pick(Self.patterns))\"/>"
            + "</xs:restriction></xs:simpleType>")
        parts.append("<xs:simpleType name=\"s1\"><xs:restriction base=\"s0\"/></xs:simpleType>")
        // A base complex type and a complexContent restriction of it (the particle
        // restriction core), plus an extension that may cycle.
        parts.append("<xs:complexType name=\"B\">\(modelGroup(3))</xs:complexType>")
        parts.append("<xs:complexType name=\"R\"><xs:complexContent><xs:restriction base=\"B\">\(modelGroup(3))"
            + "</xs:restriction></xs:complexContent></xs:complexType>")
        parts.append("<xs:element name=\"root\" type=\"\(pick(["B", "R", "s0", "xs:string"]))\"/>")
        parts.append("</xs:schema>")
        return parts.joined()
    }

    private mutating func instanceElement(_ name: String, _ depth: Int) -> String {
        if depth <= 0 || toss() {
            return toss() ? "<\(name)/>" : "<\(name)>\(pick(["", "x", "42", "true", "  "]))</\(name)>"
        }
        let children = (0 ..< Int.random(in: 0 ... 3, using: &rng)).map { _ in instanceElement(pick(Self.names), depth - 1) }.joined()
        return "<\(name)>\(children)</\(name)>"
    }

    mutating func instance() -> String {
        let namespace = toss() ? " xmlns=\"urn:t\"" : ""
        let children = (0 ..< Int.random(in: 0 ... 3, using: &rng)).map { _ in instanceElement(pick(Self.names), 3) }.joined()
        return "<root\(namespace)>\(children)</root>"
    }
}

/// Generative robustness fuzzing for the schema engine and parser. The bar is
/// interactive safety (production-readiness stopper 4): on arbitrary, possibly
/// hostile input the validator must never crash and must always terminate. A
/// trap aborts the test process (a visible failure); the `.timeLimit` trait
/// turns a true hang into a failure rather than a blocked run. Seeds are fixed
/// so any failure reproduces. No reference oracle is asserted here: this
/// characterizes termination and crash-freedom, not verdict correctness.
@Suite("Schema fuzz (generative robustness)")
struct SchemaFuzzTests {
    // The harness finds native crashes and hangs; under the ~30x-slower WASI
    // runtime a handful of iterations only proves it compiles and runs there, so
    // the counts drop to keep that gate fast. Raise the native bounds for a
    // deeper, longer fuzz campaign.
    #if os(WASI)
        private static let schemaIterations: UInt64 = 15
        private static let parserIterations: UInt64 = 40
    #else
        private static let schemaIterations: UInt64 = 250
        private static let parserIterations: UInt64 = 600
    #endif

    // The `.timeLimit` trait (native hang detection) is not supported by the
    // single-threaded WASI test runtime, so it is applied only off-WASI; on WASI
    // the engine's own occurrence/state caps still guarantee termination.
    #if os(WASI)
        @Test("Schema compile and instance validation never crash or hang")
    #else
        @Test("Schema compile and instance validation never crash or hang", .timeLimit(.minutes(1)))
    #endif
    func test_schemaAndInstanceFuzz() {
        for seed in UInt64(1) ... Self.schemaIterations {
            var generator = SchemaGenerator(rng: SeededRNG(seed: seed))
            let xsd = generator.schema()
            // The schema text is also valid XML; the parser must handle it too.
            _ = try? PureXML.parse(xsd)
            guard let document = try? PureXML.Schema.Document(xsd) else { continue }
            let xml = generator.instance()
            let errors = (try? document.validate(xml)) ?? []
            _ = errors.isEmpty
            _ = try? document.validate(streaming: xml)
        }
    }

    #if os(WASI)
        @Test("The parser never crashes on arbitrary byte sequences")
    #else
        @Test("The parser never crashes on arbitrary byte sequences", .timeLimit(.minutes(1)))
    #endif
    func test_parserByteFuzz() {
        let palette = Array("<>/=\"'?! &;:-[]xmlABC\n\t".utf8)
        for seed in UInt64(1) ... Self.parserIterations {
            var rng = SeededRNG(seed: seed)
            let length = Int.random(in: 0 ... 200, using: &rng)
            var bytes: [UInt8] = []
            bytes.reserveCapacity(length)
            for _ in 0 ..< length {
                bytes.append(Bool.random(using: &rng) ? palette[Int.random(in: 0 ..< palette.count, using: &rng)] : UInt8.random(in: 0 ... 255, using: &rng))
            }
            _ = try? PureXML.parse(bytes: bytes)
        }
    }
}
