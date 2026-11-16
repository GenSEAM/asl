(module asl-vdom/tests/html2CoverTest
  :x [runTests]
  :i [(aslVdom/html :a h)])

fn testDPlainNormal -> Bool
  (let [(node (h/dPlain (list (h/t "hi")))) (out (h/vnodeToHtml node))] (assert (= out "<div>hi</div>") "dPlain normal wraps children in div") true)

fn testDPlainEmpty -> Bool
  (let [(node (h/dPlain (list))) (out (h/vnodeToHtml node))] (assert (= out "<div></div>") "dPlain empty children yields empty div") true)

fn testSPlainNormal -> Bool
  (let [(node (h/sPlain (list (h/t "x")))) (out (h/vnodeToHtml node))] (assert (= out "<span>x</span>") "sPlain normal wraps children in span") true)

fn testSPlainEmpty -> Bool
  (let [(node (h/sPlain (list))) (out (h/vnodeToHtml node))] (assert (= out "<span></span>") "sPlain empty children yields empty span") true)

fn testBPlainNormal -> Bool
  (let [(node (h/bPlain (list (h/t "go")))) (out (h/vnodeToHtml node))] (assert (= out "<button>go</button>") "bPlain normal wraps children in button") true)

fn testBPlainEmpty -> Bool
  (let [(node (h/bPlain (list))) (out (h/vnodeToHtml node))] (assert (= out "<button></button>") "bPlain empty children yields empty button") true)

fn testBtnPlainNormal -> Bool
  (let [(node (h/btnPlain (list (h/t "ok")))) (out (h/vnodeToHtml node))] (assert (= out "<button>ok</button>") "btnPlain normal wraps children in button") true)

fn testBtnPlainEmpty -> Bool
  (let [(node (h/btnPlain (list))) (out (h/vnodeToHtml node))] (assert (= out "<button></button>") "btnPlain empty children yields empty button") true)

fn testFtrPlainNormal -> Bool
  (let [(node (h/ftrPlain (list (h/t "end")))) (out (h/vnodeToHtml node))] (assert (= out "<footer>end</footer>") "ftrPlain normal wraps children in footer") true)

fn testFtrPlainEmpty -> Bool
  (let [(node (h/ftrPlain (list))) (out (h/vnodeToHtml node))] (assert (= out "<footer></footer>") "ftrPlain empty children yields empty footer") true)

fn testFrmPlainNormal -> Bool
  (let [(node (h/frmPlain (list (h/t "f")))) (out (h/vnodeToHtml node))] (assert (= out "<form>f</form>") "frmPlain normal wraps children in form") true)

fn testFrmPlainEmpty -> Bool
  (let [(node (h/frmPlain (list))) (out (h/vnodeToHtml node))] (assert (= out "<form></form>") "frmPlain empty children yields empty form") true)

fn testArtPlainNormal -> Bool
  (let [(node (h/artPlain (list (h/t "a")))) (out (h/vnodeToHtml node))] (assert (= out "<article>a</article>") "artPlain normal wraps children in article") true)

fn testArtPlainEmpty -> Bool
  (let [(node (h/artPlain (list))) (out (h/vnodeToHtml node))] (assert (= out "<article></article>") "artPlain empty children yields empty article") true)

fn testTblPlainNormal -> Bool
  (let [(node (h/tblPlain (list (h/t "r")))) (out (h/vnodeToHtml node))] (assert (= out "<table>r</table>") "tblPlain normal wraps children in table") true)

fn testTblPlainEmpty -> Bool
  (let [(node (h/tblPlain (list))) (out (h/vnodeToHtml node))] (assert (= out "<table></table>") "tblPlain empty children yields empty table") true)

fn testLblPlainNormal -> Bool
  (let [(node (h/lblPlain (list (h/t "l")))) (out (h/vnodeToHtml node))] (assert (= out "<label>l</label>") "lblPlain normal wraps children in label") true)

fn testLblPlainEmpty -> Bool
  (let [(node (h/lblPlain (list))) (out (h/vnodeToHtml node))] (assert (= out "<label></label>") "lblPlain empty children yields empty label") true)

fn testElPlainNormal -> Bool
  (let [(node (h/elPlain "ul" (list (h/t "i")))) (out (h/vnodeToHtml node))] (assert (= out "<ul>i</ul>") "elPlain normal wraps children in given tag") true)

fn testElPlainEmpty -> Bool
  (let [(node (h/elPlain "p" (list))) (out (h/vnodeToHtml node))] (assert (= out "<p></p>") "elPlain empty children yields empty element") true)

fn testElPlainVoidTag -> Bool
  (let [(node (h/elPlain "br" (list))) (out (h/vnodeToHtml node))] (assert (= out "<br>") "elPlain with void tag serializes without closing tag") true)

fn testEscapeHtmlNormal -> Bool
  (let [(out (h/escapeHtml "a<b>c"))] (assert (= out "a&lt;b&gt;c") "escapeHtml escapes angle brackets") true)

fn testEscapeHtmlAllChars -> Bool
  (let [(out (h/escapeHtml "&<>\"'"))] (assert (= out "&amp;&lt;&gt;&quot;&#39;") "escapeHtml escapes all five special chars") true)

fn testEscapeHtmlEmpty -> Bool
  (let [(out (h/escapeHtml ""))] (assert (= out "") "escapeHtml of empty string is empty") true)

fn testEscapeHtmlPlain -> Bool
  (let [(out (h/escapeHtml "plain text"))] (assert (= out "plain text") "escapeHtml leaves plain text unchanged") true)

fn testIsVoidTagTrue -> Bool
  (let [(r1 (h/isVoidTag? "br")) (r2 (h/isVoidTag? "img")) (r3 (h/isVoidTag? "input"))] (assert r1 "br is a void tag") (assert r2 "img is a void tag") (assert r3 "input is a void tag") true)

fn testIsVoidTagFalse -> Bool
  (let [(r1 (h/isVoidTag? "div")) (r2 (h/isVoidTag? "")) (r3 (h/isVoidTag? "BR"))] (assert (not r1) "div is not a void tag") (assert (not r2) "empty string is not a void tag") (assert (not r3) "case-sensitive: BR is not a void tag") true)

fn testIsVoidTagBoundary -> Bool
  (let [(r1 (h/isVoidTag? "wbr")) (r2 (h/isVoidTag? "area")) (r3 (h/isVoidTag? "track"))] (assert r1 "wbr is a void tag") (assert r2 "area is a void tag") (assert r3 "track is a void tag") true)

fn testAttrsToHtmlNormal -> Bool
  (let [(out (h/attrsToHtml (h/attrsOf (list (h/attr "id" "x")))))] (assert (= out " id=\"x\"") "attrsToHtml normal yields leading space and quoted value") true)

fn testAttrsToHtmlEmpty -> Bool
  (let [(out (h/attrsToHtml (h/attrsEmpty)))] (assert (= out "") "attrsToHtml of empty map is empty string") true)

fn testAttrsToHtmlBoolean -> Bool
  (let [(outT (h/attrsToHtml (h/attrsOf (list (h/attr "disabled" "true"))))) (outF (h/attrsToHtml (h/attrsOf (list (h/attr "disabled" "false")))))] (assert (= outT " disabled") "true boolean attr serializes as bare name") (assert (= outF "") "false boolean attr is omitted") true)

fn testAttrsToHtmlEscapesValue -> Bool
  (let [(out (h/attrsToHtml (h/attrsOf (list (h/attr "title" "a&b")))))] (assert (= out " title=\"a&amp;b\"") "attrsToHtml escapes attribute values") true)

fn testAttrsToHtmlMultiple -> Bool
  (let [(out (h/attrsToHtml (h/attrsOf (list (h/attr "id" "a") (h/attr "class" "b")))))] (assert (stringContains? out "id=\"a\"") "multi-attr output contains id") (assert (stringContains? out "class=\"b\"") "multi-attr output contains class") true)

fn runTests -> Bool
  (and (testDPlainNormal) (and (testDPlainEmpty) (and (testSPlainNormal) (and (testSPlainEmpty) (and (testBPlainNormal) (and (testBPlainEmpty) (and (testBtnPlainNormal) (and (testBtnPlainEmpty) (and (testFtrPlainNormal) (and (testFtrPlainEmpty) (and (testFrmPlainNormal) (and (testFrmPlainEmpty) (and (testArtPlainNormal) (and (testArtPlainEmpty) (and (testTblPlainNormal) (and (testTblPlainEmpty) (and (testLblPlainNormal) (and (testLblPlainEmpty) (and (testElPlainNormal) (and (testElPlainEmpty) (and (testElPlainVoidTag) (and (testEscapeHtmlNormal) (and (testEscapeHtmlAllChars) (and (testEscapeHtmlEmpty) (and (testEscapeHtmlPlain) (and (testIsVoidTagTrue) (and (testIsVoidTagFalse) (and (testIsVoidTagBoundary) (and (testAttrsToHtmlNormal) (and (testAttrsToHtmlEmpty) (and (testAttrsToHtmlBoolean) (and (testAttrsToHtmlEscapesValue) (testAttrsToHtmlMultiple)))))))))))))))))))))))))))))))))
