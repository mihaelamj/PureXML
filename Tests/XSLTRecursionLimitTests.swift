import Testing
@testable import PureXML

/// The XSLT evaluator is iterative, so template recursion is bounded by heap, not
/// the native stack (#356). Deep recursion that would once have overflowed the
/// stack now succeeds, even here where swift-testing runs on a small Task stack;
/// only a runaway/infinite recursion (whose result tree would grow without bound)
/// fails gracefully at the configurable `maxTemplateDepth`.
@Suite("XSLT template recursion")
struct XSLTRecursionTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    /// A stylesheet whose named template recurses `count` times, driving the
    /// recursion from the passed parameter (a stand-in for `count(//x)`).
    private func recursiveStylesheet(_ count: Int) -> String {
        "<xsl:stylesheet version=\"1.0\" \(xsl)>"
            + "<xsl:template match=\"/\"><xsl:call-template name=\"d\">"
            + "<xsl:with-param name=\"n\" select=\"\(count)\"/></xsl:call-template></xsl:template>"
            + "<xsl:template name=\"d\"><xsl:param name=\"n\"/>"
            + "<xsl:if test=\"$n &gt; 0\"><x><xsl:call-template name=\"d\">"
            + "<xsl:with-param name=\"n\" select=\"$n - 1\"/></xsl:call-template></x></xsl:if></xsl:template>"
            + "</xsl:stylesheet>"
    }

    @Test("deep recursion succeeds on a small stack instead of overflowing")
    func test_deepRecursionSucceeds() throws {
        // 5000 levels far exceeds what the recursive engine survived on a Task
        // stack (a few hundred); the iterative engine builds it on the heap.
        let out = try PureXML.XSLT.transform(stylesheet: recursiveStylesheet(5000), source: "<r/>")
        #expect(out.components(separatedBy: "<x>").count - 1 == 4999)
    }

    @Test("a runaway recursion fails gracefully at the configured limit")
    func test_runawayFailsGracefully() {
        // A low limit stands in for an unbounded recursion: it trips the guard
        // cheaply and throws rather than building without bound.
        #expect(throws: PureXML.XSLT.XSLTError.recursionLimitExceeded(100)) {
            _ = try PureXML.XSLT.transform(stylesheet: recursiveStylesheet(5000), source: "<r/>", maxTemplateDepth: 100)
        }
    }

    @Test("recursion within the limit transforms normally")
    func test_withinLimitSucceeds() throws {
        let out = try PureXML.XSLT.transform(stylesheet: recursiveStylesheet(100), source: "<r/>")
        #expect(out.components(separatedBy: "<x>").count - 1 == 99)
    }

    @Test("an identity transform of the deepest permitted source runs on a small stack")
    func test_identityOfMaxDepthSource() throws {
        let depth = 254 // the parser permits up to maxDepth (256) nesting.
        let src = String(repeating: "<a>", count: depth) + "leaf" + String(repeating: "</a>", count: depth)
        let sheet = "<xsl:stylesheet version=\"1.0\" \(xsl)>"
            + "<xsl:template match=\"@*|node()\"><xsl:copy><xsl:apply-templates select=\"@*|node()\"/></xsl:copy></xsl:template>"
            + "</xsl:stylesheet>"
        let out = try PureXML.XSLT.transform(stylesheet: sheet, source: src)
        #expect(out.contains("leaf"))
        #expect(out.contains(String(repeating: "<a>", count: depth)))
    }
}
