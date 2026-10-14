(module asl-html/tests/markdownTest
  :x [runTests]
  :i [(asl-html/html :a h) (asl-html/markdown :a md)])

fn html src: String -> String
  (stringJoin (map h/render (md/blocks (stringLines src))) "")

fn runTests -> Bool
  (do
    (assert (= (html "Some `code` and **bold** and [a link](/docs).") "<p>Some <code>code</code> and <strong>bold</strong> and <a href=\"/docs\">a link</a>.</p>") "inline spans")
    (assert (= (html "## Title\n\n- one\n- two") "<h2>Title</h2><ul><li>one</li><li>two</li></ul>") "heading and list")
    (assert (= (html "```asl\n(a < b)\n```") "<pre data-lang=\"asl\"><code>(a &lt; b)</code></pre>") "fence is escaped")
    (assert (= (html "| A | B |\n|---|---|\n| 1 | 2 |") "<div class=\"tablewrap\"><table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody></table></div>") "table")
    (assert (= (html "1. first\n2. second") "<ol><li>first</li><li>second</li></ol>") "ordered list")
    (assert (= (html "# Dropped title\nline one\nline two") "<p>line one line two</p>") "h1 dropped, lines joined")
    (assert (= (html "an unclosed `tick") "<p>an unclosed `tick</p>") "unclosed mark stays text")
    (assert (= (html "<script>") "<p>&lt;script&gt;</p>") "raw html is text")
    (assert (= (html "*By GenSEAM* and **bold**") "<p><em>By GenSEAM</em> and <strong>bold</strong></p>") "emphasis and strong")
    true)
