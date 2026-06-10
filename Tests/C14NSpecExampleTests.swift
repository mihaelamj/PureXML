@testable import PureXML
import Testing

/// The worked examples of Canonical XML 1.0 section 3 (W3C Recommendation,
/// https://www.w3.org/TR/xml-c14n, W3C Software and Document License), run as
/// input/expected-output vectors (#132). Each test cites its example number.
@Suite("C14N 1.0 spec examples")
struct C14NSpecExampleTests {
    private func canonical(
        _ input: String,
        comments: Bool = false,
        resolver: PureXML.Parsing.EntityResolver = .refusing,
    ) throws -> String {
        var options = PureXML.Canonical.Options.inclusive
        options.includeComments = comments
        // C14N input is the validating-processor view: DTD defaults applied.
        let node = try PureXML.parseApplyingInternalDTDDefaults(input, resolver: resolver)
        return PureXML.Canonical.canonicalize(node, options: options)
    }

    @Test("3.1: PIs, comments, and content outside the document element")
    func test_example31() throws {
        let input = """
        <?xml version="1.0"?>

        <?xml-stylesheet   href="doc.xsl"
           type="text/xsl"   ?>

        <!DOCTYPE doc SYSTEM "doc.dtd">

        <doc>Hello, world!<!-- Comment 1 --></doc>

        <?pi-without-data     ?>

        <!-- Comment 2 -->

        <!-- Comment 3 -->
        """
        let uncommented = """
        <?xml-stylesheet href="doc.xsl"
           type="text/xsl"   ?>
        <doc>Hello, world!</doc>
        <?pi-without-data?>
        """
        let commented = """
        <?xml-stylesheet href="doc.xsl"
           type="text/xsl"   ?>
        <doc>Hello, world!<!-- Comment 1 --></doc>
        <?pi-without-data?>
        <!-- Comment 2 -->
        <!-- Comment 3 -->
        """
        #expect(try canonical(input) == uncommented)
        #expect(try canonical(input, comments: true) == commented)
    }

    @Test("3.2: whitespace in document content is preserved")
    func test_example32() throws {
        let input = """
        <doc>
           <clean>   </clean>
           <dirty>   A   B   </dirty>
           <mixed>
              A
              <clean>   </clean>
              B
              <dirty>   A   B   </dirty>
              C
           </mixed>
        </doc>
        """
        // The canonical form is byte-identical for this input.
        #expect(try canonical(input) == input)
    }

    @Test("3.3: start and end tags, attribute sorting, superfluous namespaces")
    func test_example33() throws {
        let input = """
        <!DOCTYPE doc [<!ATTLIST e9 attr CDATA "default">]>
        <doc>
           <e1   />
           <e2   ></e2>
           <e3   name = "elem3"   id="elem3"   />
           <e4   name="elem4"   id="elem4"   ></e4>
           <e5 a:attr="out" b:attr="sorted" attr2="all" attr="I'm"
              xmlns:b="http://www.ietf.org"
              xmlns:a="http://www.w3.org"
              xmlns="http://example.org"/>
           <e6 xmlns="" xmlns:a="http://www.w3.org">
              <e7 xmlns="http://www.ietf.org">
                 <e8 xmlns="" xmlns:a="http://www.w3.org">
                    <e9 xmlns="" xmlns:a="http://www.ietf.org"/>
                 </e8>
              </e7>
           </e6>
        </doc>
        """
        let expected = """
        <doc>
           <e1></e1>
           <e2></e2>
           <e3 id="elem3" name="elem3"></e3>
           <e4 id="elem4" name="elem4"></e4>
           <e5 xmlns="http://example.org" xmlns:a="http://www.w3.org" xmlns:b="http://www.ietf.org" attr="I'm" attr2="all" b:attr="sorted" a:attr="out"></e5>
           <e6 xmlns:a="http://www.w3.org">
              <e7 xmlns="http://www.ietf.org">
                 <e8 xmlns="">
                    <e9 xmlns:a="http://www.ietf.org" attr="default"></e9>
                 </e8>
              </e7>
           </e6>
        </doc>
        """
        #expect(try canonical(input) == expected)
    }

    @Test("3.4: character modifications and character references")
    func test_example34() throws {
        let input = """
        <!DOCTYPE doc [
        <!ATTLIST normId id ID #IMPLIED>
        <!ATTLIST normNames attr NMTOKENS #IMPLIED>
        ]>
        <doc>
           <text>First line&#x0d;&#10;Second line</text>
           <value>&#x32;</value>
           <compute><![CDATA[value>"0" && value<"10" ?"valid":"error"]]></compute>
           <compute expr='value>"0" &amp;&amp; value&lt;"10" ?"valid":"error"'>valid</compute>
           <norm attr=' &apos;   &#x20;&#13;&#xa;&#9;   &apos; '/>
        </doc>
        """
        let expected = """
        <doc>
           <text>First line&#xD;
        Second line</text>
           <value>2</value>
           <compute>value&gt;"0" &amp;&amp; value&lt;"10" ?"valid":"error"</compute>
           <compute expr="value>&quot;0&quot; &amp;&amp; value&lt;&quot;10&quot; ?&quot;valid&quot;:&quot;error&quot;">valid</compute>
           <norm attr=" '    &#xD;&#xA;&#x9;   ' "></norm>
        </doc>
        """
        #expect(try canonical(input) == expected)
    }

    @Test("3.5: entity references are expanded")
    func test_example35() throws {
        let input = """
        <!DOCTYPE doc [
        <!ATTLIST doc attrExtEnt ENTITY #IMPLIED>
        <!ENTITY ent1 "Hello">
        <!ENTITY ent2 SYSTEM "world.txt">
        <!ENTITY entExt SYSTEM "earth.gif" NDATA gif>
        <!NOTATION gif SYSTEM "viewgif.exe">
        ]>
        <doc attrExtEnt="entExt">
           &ent1;, &ent2;!
        </doc>
        """
        let expected = """
        <doc attrExtEnt="entExt">
           Hello, world!
        </doc>
        """
        let resolver = PureXML.Parsing.EntityResolver(
            resolveEntity: { name, _ in name == "ent2" ? "world" : nil },
            resolveExternalSubset: { _ in nil },
        )
        #expect(try canonical(input, resolver: resolver) == expected)
    }

    @Test("3.6: output is UTF-8 regardless of input encoding")
    func test_example36() throws {
        // The declaration names ISO-8859-1 and the byte 0xA9 is the copyright
        // sign there; the canonical form carries the UTF-8 character.
        var bytes = Array("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n<doc>".utf8)
        bytes.append(0xA9)
        bytes += Array("</doc>".utf8)
        let source = try PureXML.Parsing.ByteDecoder.decode(bytes)
        let node = try PureXML.parse(source)
        #expect(PureXML.Canonical.canonicalize(node) == "<doc>\u{A9}</doc>")
    }
}
