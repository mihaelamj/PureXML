import Foundation
import Testing
@testable import PureXML

/// XSLT template recursion is bounded so an unbounded recursive template (whose
/// depth can be driven by source data) fails gracefully instead of overflowing
/// the stack (#356). Source *nesting* depth is already bounded by the parser's
/// `maxDepth`, so it is not the exposure; a recursive named template is.
///
/// These run on a dedicated large-stack thread: the recursion limit (300) is
/// above what swift-testing's small Task stack holds, so the guard must be given
/// a production-sized stack to fire on rather than the test harness overflowing
/// first. That is exactly the gap the limit closes on a normal 8 MB main thread.
@Suite("XSLT template recursion limit")
struct XSLTRecursionLimitTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    /// Runs `body` on a thread with a large stack and returns its result, so the
    /// recursion guard is exercised on a production-sized stack.
    private func onLargeStack<T: Sendable>(_ body: @escaping @Sendable () -> T) -> T {
        let box = Box<T>()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.value = body()
            done.signal()
        }
        thread.stackSize = 64 * 1024 * 1024
        thread.start()
        done.wait()
        guard let value = box.value else { preconditionFailure("the worker thread produced no result") }
        return value
    }

    private final class Box<T>: @unchecked Sendable { var value: T? }

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

    @Test("recursion past the default limit throws rather than crashing")
    func test_deepRecursionFailsGracefully() {
        let error: (any Error)? = onLargeStack {
            do {
                _ = try PureXML.XSLT.transform(stylesheet: recursiveStylesheet(5000), source: "<r/>")
                return nil
            } catch {
                return error
            }
        }
        #expect(error as? PureXML.XSLT.XSLTError == .recursionLimitExceeded(PureXML.XSLT.defaultMaxTemplateDepth))
    }

    @Test("recursion within the limit transforms normally")
    func test_shallowRecursionSucceeds() {
        let out = onLargeStack { (try? PureXML.XSLT.transform(stylesheet: recursiveStylesheet(100), source: "<r/>")) ?? "" }
        #expect(out.contains("<x>"))
    }

    @Test("a raised maxTemplateDepth allows deeper legitimate recursion")
    func test_configurableLimit() {
        let out = onLargeStack {
            (try? PureXML.XSLT.transform(stylesheet: recursiveStylesheet(1000), source: "<r/>", maxTemplateDepth: 4000)) ?? ""
        }
        // Recursion went far past the default limit of 300 (it would otherwise have
        // thrown), producing ~1000 nested <x> elements.
        #expect(out.components(separatedBy: "<x>").count - 1 > 900)
    }

    @Test("an identity transform of the deepest permitted source still runs")
    func test_identityOfMaxDepthSource() {
        let depth = 254 // the parser permits up to maxDepth (256) nesting.
        let src = String(repeating: "<a>", count: depth) + "leaf" + String(repeating: "</a>", count: depth)
        let sheet = "<xsl:stylesheet version=\"1.0\" \(xsl)>"
            + "<xsl:template match=\"@*|node()\"><xsl:copy><xsl:apply-templates select=\"@*|node()\"/></xsl:copy></xsl:template>"
            + "</xsl:stylesheet>"
        let out = onLargeStack { (try? PureXML.XSLT.transform(stylesheet: sheet, source: src)) ?? "" }
        #expect(out.contains("leaf"))
        #expect(out.contains(String(repeating: "<a>", count: depth)))
    }
}
