@testable import PureXML
import Testing

@Suite("HTML5 select content model")
struct HTMLSelectTests {
    private func body(_ html: String) -> String {
        let full = PureXML.HTML.serialize(PureXML.HTML.parseDocument(html))
        let wrapper = "<html><head></head><body>"
        guard full.hasPrefix(wrapper), full.hasSuffix("</body></html>") else { return full }
        return String(full.dropFirst(wrapper.count).dropLast("</body></html>".count))
    }

    @Test("Options nest and close one another")
    func test_options() {
        #expect(body("<select><option>a<option>b</select>") == "<select><option>a</option><option>b</option></select>")
    }

    @Test("optgroup closes an open option")
    func test_optgroup() {
        #expect(body("<select><option>1<optgroup><option>2</select>") == "<select><option>1</option><optgroup><option>2</option></optgroup></select>")
    }

    @Test("A nested select closes the open one")
    func test_nestedSelect() {
        #expect(body("<select><select>") == "<select></select>")
    }

    @Test("An input closes the select and is placed after it")
    func test_inputClosesSelect() {
        #expect(body("<select><option>a<input></select>") == "<select><option>a</option></select><input>")
    }

    @Test("A table cell closes a select that is inside a table")
    func test_selectInTable() {
        let expected = "<table><tbody><tr><td>x<select><option>a</option></select></td><td>y</td></tr></tbody></table>"
        #expect(body("<table><tr><td>x<select><option>a<td>y</table>") == expected)
    }
}
