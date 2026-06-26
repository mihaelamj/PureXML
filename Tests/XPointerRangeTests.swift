import Testing
@testable import PureXML

@Suite("XPointer range(), range-to(), string-range()")
struct XPointerRangeTests {
    private func doc() throws -> PureXML.Model.Node {
        try PureXML.parse(
            "<book>"
                + "<chapter id=\"intro\"><para>first</para><para>second</para></chapter>"
                + "<chapter id=\"main\"><para>third</para></chapter>"
                + "</book>",
        )
    }

    private func ranges(_ pointer: String) throws -> [PureXML.XPointer.Range] {
        try PureXML.XPointer.evaluateRanges(pointer, over: doc())
    }

    @Test("range() yields the covering range of each selected node")
    func test_covering() throws {
        let result = try ranges("xpointer(range(//chapter[@id='intro']))")
        #expect(result.count == 1)
        #expect(result.first?.text == "firstsecond")
    }

    @Test("range-to() spans the sibling run between two locations")
    func test_rangeToSiblings() throws {
        let result = try ranges("xpointer(//para[1]/range-to(//para[2]))")
        #expect(result.count == 1)
        // The two para siblings inside the intro chapter, in document order.
        #expect(result.first?.text == "firstsecond")
        #expect(result.first?.nodes.count == 2)
    }

    @Test("range-to() across chapters falls back to the two boundary nodes")
    func test_rangeToBoundary() throws {
        let result = try ranges("xpointer(id('intro')/range-to(id('main')))")
        #expect(result.count == 1)
        #expect(result.first?.nodes.count == 2)
        #expect(result.first?.text == "firstsecondthird")
    }

    @Test("string-range() returns a character range per match")
    func test_stringRange() throws {
        let result = try ranges("xpointer(string-range(//para, \"ir\"))")
        // "first" and "third" both contain "ir".
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.text == "ir" })
    }

    @Test("string-range() matches are non-overlapping")
    func test_stringRangeNonOverlapping() throws {
        // "aa" in "aaaaa": the scan emits a match then resumes past it, so it
        // finds positions 0 and 2 (not the overlapping 1 and 3). The linear KMP
        // search must keep that advance-by-needle behavior.
        let xml = try PureXML.parse("<d>aaaaa</d>")
        let result = try PureXML.XPointer.evaluateRanges("xpointer(string-range(/d, \"aa\"))", over: xml)
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.text == "aa" })
    }

    @Test("string-range() finds a match that needs failure-function backtracking")
    func test_stringRangeBacktrack() throws {
        // In "abcabcabd" the needle "abcabd" matches only at index 3; reaching it
        // requires backtracking after the partial "abcab" at index 0 mismatches.
        let xml = try PureXML.parse("<d>abcabcabd</d>")
        let result = try PureXML.XPointer.evaluateRanges("xpointer(string-range(/d, \"abcabd\"))", over: xml)
        #expect(result.count == 1)
        #expect(result.first?.text == "abcabd")
    }

    @Test("string-range() honors offset and length")
    func test_stringRangeOffsetLength() throws {
        // From the "ir" match in "first", start at offset 2 (the 'r') for length 1.
        let result = try ranges("xpointer(string-range(//chapter[@id='intro']/para[1], \"ir\", 2, 1))")
        #expect(result.count == 1)
        #expect(result.first?.text == "r")
    }

    @Test("An xmlns() binding applies to a following range part")
    func test_namespaceBoundRange() throws {
        let xml = try PureXML.parse("<d xmlns:x=\"urn:x\"><x:a>one</x:a><x:a>two</x:a></d>")
        let result = try PureXML.XPointer.evaluateRanges("xmlns(x=urn:x)xpointer(range(//x:a[1]))", over: xml)
        #expect(result.count == 1)
        #expect(result.first?.text == "one")
    }

    @Test("A non-range expression yields no ranges")
    func test_noRanges() throws {
        #expect(try ranges("xpointer(//para)").isEmpty)
    }
}
