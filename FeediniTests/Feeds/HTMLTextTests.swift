import Testing

@testable import Feedini

struct HTMLTextTests {
    @Test func keepsParagraphsLineBreaksAndListItems() {
        let html =
            "<h2>Title</h2><p>One <b>bold</b>\n  word.</p><p>Two<br>lines</p><ol><li>first</li><li>second</li></ol>"
        #expect(HTMLText.plainText(html) == "Title\n\nOne bold word.\n\nTwo\nlines\n\n• first\n• second")
    }

    @Test func dropsScriptsStylesAndComments() {
        let html = "<p>Before</p><script type=\"x\">var a = '<p>';</script><style>p{}</style><!-- <p>no</p> -->After"
        #expect(HTMLText.plainText(html) == "Before\n\nAfter")
    }

    @Test func keepsSpacesBetweenInlineElements() {
        #expect(HTMLText.plainText("<a href=\"x\">link</a> <em>text</em>") == "link text")
        #expect(HTMLText.plainText("A<span>B</span> C") == "AB C")
    }

    @Test func keepsAngleBracketsThatAreNotTags() {
        #expect(HTMLText.plainText("1 < 2 and 3 > 2") == "1 < 2 and 3 > 2")
        #expect(HTMLText.plainText("unclosed <b") == "unclosed <b")
        #expect(HTMLText.plainText("ends with <") == "ends with <")
    }

    @Test func decodesEntitiesOnlyInText() {
        #expect(
            HTMLText.plainText("<p title=\"&amp;\">Fish &amp; chips&nbsp;&#8211; &#x1F3A9;</p>") == "Fish & chips – 🎩")
    }

    @Test func emptyAndWhitespaceOnlyInputGivesEmptyText() {
        #expect(HTMLText.plainText("") == "")
        #expect(HTMLText.plainText("  <p> </p>\n<br/> ") == "")
        #expect(HTMLText.plainText("<img src=\"x.jpg\"/>") == "")
    }

    @Test func decodesKnownEntitiesAndLeavesTheRest() {
        #expect(HTMLText.decodeEntities("&lt;&gt;&quot;&apos;&scaron;&hellip;") == "<>\"'š…")
        #expect(HTMLText.decodeEntities("&#38;&#X26;&#x26;") == "&&&")
        #expect(HTMLText.decodeEntities("AT&T & &bogus; &#xZZ; &#99999999;") == "AT&T & &bogus; &#xZZ; &#99999999;")
        #expect(HTMLText.decodeEntities("no entities") == "no entities")
        #expect(HTMLText.decodeEntities("&averyveryverylongname;") == "&averyveryverylongname;")
    }

    @Test func excerptCutsAtAWordBoundary() {
        #expect(HTMLText.excerpt("Short text.", limit: 20) == "Short text.")
        #expect(HTMLText.excerpt("One two three four, five", limit: 19) == "One two three four…")
        #expect(HTMLText.excerpt("First paragraph.\n\nSecond one", limit: 100) == "First paragraph. Second one")
        #expect(HTMLText.excerpt("Supercalifragilistic", limit: 5) == "Super…")
    }
}
