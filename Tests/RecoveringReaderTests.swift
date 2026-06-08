@testable import PureXML
import Testing

/// The recovering reader (`PureXML.read`) never throws and never crashes: it
/// returns the maximal best-effort tree plus one located diagnostic per problem.
/// Its recovery is deterministic, so every assertion here pins an exact result.
@Suite("Recovering reader")
struct RecoveringReaderTests {
    @Test("Well-formed input matches the strict parser with no diagnostics")
    func test_wellFormed() throws {
        let xml = "<a><b>x</b></a>"
        let result = PureXML.read(xml)
        #expect(result.diagnostics.isEmpty)
        #expect(try result.node == PureXML.parse(xml))
    }

    @Test("Truncated input is closed into a best-effort tree with one diagnostic")
    func test_truncated() throws {
        let result = PureXML.read("<a><b>x")
        #expect(try result.node == PureXML.parse("<a><b>x</b></a>"))
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].mark != nil)
        #expect(result.diagnostics[0].message.contains("unexpected end of input"))
    }

    @Test("A mismatched end tag is reported and the content is salvaged")
    func test_mismatchedEndTag() throws {
        let result = PureXML.read("<a><b>x</c></a>")
        #expect(try result.node == PureXML.parse("<a><b>x</b></a>"))
        #expect(result.diagnostics.count == 2)
        #expect(result.diagnostics.allSatisfy { $0.message.contains("expected </b>") })
    }

    @Test("A duplicate attribute is dropped but the element is kept")
    func test_duplicateAttributeKeepsElement() throws {
        let result = PureXML.read("<a id='1' id='2'>y</a>")
        #expect(try result.node == PureXML.parse("<a id='1'>y</a>"))
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].message.contains("duplicate attribute 'id'"))
    }

    @Test("A mismatched end tag pops to the matching ancestor, closing nested elements")
    func test_popToMatch() throws {
        let result = PureXML.read("<a><b><c>x</b></a>")
        #expect(try result.node == PureXML.parse("<a><b><c>x</c></b></a>"))
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].message.contains("expected </c> but found </b>"))
    }

    @Test("Junk around the root is dropped and the element is kept")
    func test_strayJunk() throws {
        let result = PureXML.read("garbage<a>x</a>z")
        #expect(try result.node == PureXML.parse("<a>x</a>"))
        #expect(!result.diagnostics.isEmpty)
    }

    @Test("Empty input reads as an empty document without crashing")
    func test_empty() {
        let result = PureXML.read("")
        #expect(result.node == .document([]))
        #expect(result.diagnostics.isEmpty)
    }

    @Test("Reading is deterministic: the same bytes give the same result")
    func test_deterministic() {
        for xml in ["<a><b>x</c>", "<<>><a/>", "<a x= y>z", "<a><b><c>deep"] {
            #expect(PureXML.read(xml) == PureXML.read(xml))
        }
    }

    @Test("Arbitrary and truncated input never crashes and stays deterministic")
    func test_fuzzNeverCrashes() {
        // A seeded generator (no Date/random) makes the sweep reproducible.
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func nextByte() -> UInt8 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8((state >> 33) & 0xFF)
        }
        let alphabet = Array("<>/&;\"'= \nabcxyz![]-?CDATA")
        let seed = "<root attr='v'><child>text</child><!-- c --><![CDATA[d]]></root>"

        for iteration in 0 ..< 400 {
            // Mix random characters with truncations of a valid document.
            var input = ""
            let length = Int(nextByte()) % 60
            for _ in 0 ..< length {
                input.append(alphabet[Int(nextByte()) % alphabet.count])
            }
            if iteration.isMultiple(of: 3) {
                input += String(seed.prefix(Int(nextByte()) % seed.count + 1))
            }
            let first = PureXML.read(input)
            let second = PureXML.read(input)
            // Completing without trapping is the no-crash assertion; also check the
            // result is a document and the read is deterministic.
            guard case .document = first.node else {
                Issue.record("read did not return a document for input \(input.debugDescription)")
                continue
            }
            #expect(first == second)
        }
    }
}
