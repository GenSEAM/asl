(module asl-html/tests/html1CoverTest
  :x [runTests]
  :i [(asl-html/html :a h)])

fn runTests -> Bool
  (do
    (assert (= (h/render (h/voidEl "img" [(h/src "/a.png") (h/alt "")])) "<img src=\"/a.png\" alt=\"\"/>") "voidEl self-closes a void tag")
    (assert (= (h/render (h/voidEl "br" [])) "<br>") "voidEl br with no attrs and no kids stays short")
    (assert (= (h/render (h/voidEl "div" [])) "<div></div>") "voidEl on a non-void tag still needs a closing tag")

    (assert (= (h/render (h/input [(h/valueAttr "x")])) "<input value=\"x\"/>") "valueAttr writes value")
    (assert (= (h/render (h/input [(h/valueAttr "")])) "<input value=\"\"/>") "valueAttr empty is an empty value, not a missing one")
    (assert (= (h/render (h/input [(h/valueAttr "a\"b&c")])) "<input value=\"a&quot;b&amp;c\"/>") "valueAttr escapes quotes and ampersands")

    (assert (= (h/render (h/abbr [(h/titleAttr "T")] [])) "<abbr title=\"T\"></abbr>") "titleAttr writes title")
    (assert (= (h/render (h/abbr [(h/titleAttr "")] [])) "<abbr title=\"\"></abbr>") "titleAttr empty is preserved")
    (assert (= (h/render (h/abbr [(h/titleAttr "a\"b")] [])) "<abbr title=\"a&quot;b\"></abbr>") "titleAttr escapes quotes")

    (assert (= (h/escapeText "a<b>&c") "a&lt;b&gt;&amp;c") "escapeText escapes lt gt amp")
    (assert (= (h/escapeText "") "") "escapeText of empty is empty")
    (assert (= (h/escapeText "plain text") "plain text") "escapeText leaves plain text alone")
    (assert (= (h/escapeText "&lt;") "&amp;lt;") "escapeText does not double-decode entities")

    (assert (= (h/escapeAttr "a\"b&c<d>") "a&quot;b&amp;c&lt;d&gt;") "escapeAttr escapes quotes as well as text entities")
    (assert (= (h/escapeAttr "") "") "escapeAttr of empty is empty")
    (assert (= (h/escapeAttr "plain") "plain") "escapeAttr leaves plain text alone")

    (assert (= (h/render (h/abbr [(h/titleAttr "Hyper")] [(h/text "HTML")])) "<abbr title=\"Hyper\">HTML</abbr>") "abbr normal")
    (assert (= (h/render (h/abbr [] [])) "<abbr></abbr>") "abbr empty")

    (assert (= (h/render (h/bdi [(h/attr "dir" "rtl")] [(h/text "x")])) "<bdi dir=\"rtl\">x</bdi>") "bdi normal")
    (assert (= (h/render (h/bdi [] [])) "<bdi></bdi>") "bdi empty")

    (assert (= (h/render (h/bdo [(h/attr "dir" "rtl")] [(h/text "x")])) "<bdo dir=\"rtl\">x</bdo>") "bdo normal")
    (assert (= (h/render (h/bdo [] [])) "<bdo></bdo>") "bdo empty")

    (assert (= (h/render (h/blockquote [(h/attr "cite" "https://e")] [(h/text "q")])) "<blockquote cite=\"https://e\">q</blockquote>") "blockquote normal")
    (assert (= (h/render (h/blockquote [] [])) "<blockquote></blockquote>") "blockquote empty")

    (assert (= (h/render (h/colgroup [(h/attr "span" "2")] [])) "<colgroup span=\"2\"></colgroup>") "colgroup normal")
    (assert (= (h/render (h/colgroup [] [])) "<colgroup></colgroup>") "colgroup empty")

    (assert (= (h/render (h/dataEl [(h/valueAttr "42")] [(h/text "Answer")])) "<data value=\"42\">Answer</data>") "dataEl normal")
    (assert (= (h/render (h/dataEl [] [])) "<data></data>") "dataEl empty")

    (assert (= (h/render (h/datalist [(h/id "d")] [(h/option [(h/valueAttr "1")] [(h/text "One")])])) "<datalist id=\"d\"><option value=\"1\">One</option></datalist>") "datalist normal")
    (assert (= (h/render (h/datalist [] [])) "<datalist></datalist>") "datalist empty")

    (assert (= (h/render (h/dfn [(h/titleAttr "term")] [(h/text "T")])) "<dfn title=\"term\">T</dfn>") "dfn normal")
    (assert (= (h/render (h/dfn [] [])) "<dfn></dfn>") "dfn empty")

    (assert (= (h/render (h/fieldset [(h/nameAttr "f")] [(h/legend [] [(h/text "L")])])) "<fieldset name=\"f\"><legend>L</legend></fieldset>") "fieldset normal")
    (assert (= (h/render (h/fieldset [] [])) "<fieldset></fieldset>") "fieldset empty")

    (assert (= (h/render (h/figcaption [] [(h/text "cap")])) "<figcaption>cap</figcaption>") "figcaption normal")
    (assert (= (h/render (h/figcaption [] [])) "<figcaption></figcaption>") "figcaption empty")

    (assert (= (h/render (h/hgroup [] [(h/h1 [] [(h/text "A")]) (h/h2 [] [(h/text "B")])])) "<hgroup><h1>A</h1><h2>B</h2></hgroup>") "hgroup normal")
    (assert (= (h/render (h/hgroup [] [])) "<hgroup></hgroup>") "hgroup empty")

    (assert (= (h/render (h/iframe [(h/src "https://e") (h/titleAttr "t")] [])) "<iframe src=\"https://e\" title=\"t\"></iframe>") "iframe normal")
    (assert (= (h/render (h/iframe [] [])) "<iframe></iframe>") "iframe empty")

    (assert (= (h/render (h/kbd [] [(h/text "Ctrl+C")])) "<kbd>Ctrl+C</kbd>") "kbd normal")
    (assert (= (h/render (h/kbd [] [])) "<kbd></kbd>") "kbd empty")

    (assert (= (h/render (h/legend [] [(h/text "L")])) "<legend>L</legend>") "legend normal")
    (assert (= (h/render (h/legend [] [])) "<legend></legend>") "legend empty")

    (assert (= (h/render (h/menu [] [(h/li [] [(h/text "x")])])) "<menu><li>x</li></menu>") "menu normal")
    (assert (= (h/render (h/menu [] [])) "<menu></menu>") "menu empty")

    (assert (= (h/render (h/objectEl [(h/attr "data" "movie.swf")] [(h/text "fallback")])) "<object data=\"movie.swf\">fallback</object>") "objectEl normal")
    (assert (= (h/render (h/objectEl [] [])) "<object></object>") "objectEl empty")

    (assert (= (h/render (h/optgroup [(h/attr "label" "g")] [(h/option [] [(h/text "x")])])) "<optgroup label=\"g\"><option>x</option></optgroup>") "optgroup normal")
    (assert (= (h/render (h/optgroup [] [])) "<optgroup></optgroup>") "optgroup empty")

    (assert (= (h/render (h/picture [] [(h/img [(h/src "a.png")])])) "<picture><img src=\"a.png\"/></picture>") "picture normal")
    (assert (= (h/render (h/picture [] [])) "<picture></picture>") "picture empty")

    (assert (= (h/render (h/samp [] [(h/text "out")])) "<samp>out</samp>") "samp normal")
    (assert (= (h/render (h/samp [] [])) "<samp></samp>") "samp empty")

    (assert (= (h/render (h/tbody [] [(h/tr [] [(h/td [] [(h/text "c")])])])) "<tbody><tr><td>c</td></tr></tbody>") "tbody normal")
    (assert (= (h/render (h/tbody [] [])) "<tbody></tbody>") "tbody empty")
    (assert (= (h/render (h/input [])) "<input/>") "valueAttr none path leaves the value attribute absent")
    (assert (= (h/render (h/input [(h/valueAttr "0")])) "<input value=\"0\"/>") "valueAttr preserves zero")
    (assert (= (h/render (h/input [(h/valueAttr "9223372036854775807")])) "<input value=\"9223372036854775807\"/>") "valueAttr preserves Int64 max as text")

    (assert (= (h/render (h/abbr [(h/titleAttr "0")] [])) "<abbr title=\"0\"></abbr>") "titleAttr preserves zero")
    (assert (= (h/render (h/abbr [(h/titleAttr "9223372036854775807")] [])) "<abbr title=\"9223372036854775807\"></abbr>") "titleAttr preserves Int64 max as text")

    (assert (= (h/escapeText "0") "0") "escapeText preserves zero")
    (assert (= (h/escapeText "\"'") "\"'") "escapeText leaves quotes alone")
    (assert (= (h/escapeText "<<>>") "&lt;&lt;&gt;&gt;") "escapeText escapes every boundary delimiter")
    (assert (= (h/escapeAttr "0") "0") "escapeAttr preserves zero")
    (assert (= (h/escapeAttr "'") "'") "escapeAttr leaves apostrophes alone")
    (assert (= (h/escapeAttr "\"\"") "&quot;&quot;") "escapeAttr escapes every quote")

    (assert (= (h/render (h/abbr [] [(h/text "<&>")])) "<abbr>&lt;&amp;&gt;</abbr>") "abbr escapes text children")
    (assert (= (h/render (h/b [] [(h/text "bold")])) "<b>bold</b>") "b normal")
    (assert (= (h/render (h/b [] [])) "<b></b>") "b empty")
    (assert (= (h/render (h/b [] [(h/text "0")])) "<b>0</b>") "b preserves zero text")
    (assert (= (h/render (h/b [] [(h/text "<&>")])) "<b>&lt;&amp;&gt;</b>") "b escapes text children")
    (assert (= (h/render (h/bdi [] [(h/text "<&>")])) "<bdi>&lt;&amp;&gt;</bdi>") "bdi escapes text children")
    (assert (= (h/render (h/bdo [] [(h/text "<&>")])) "<bdo>&lt;&amp;&gt;</bdo>") "bdo escapes text children")
    (assert (= (h/render (h/blockquote [(h/attr "cite" "")] [])) "<blockquote cite=\"\"></blockquote>") "blockquote preserves an empty cite boundary")
    (assert (= (h/render (h/colgroup [(h/attr "span" "0")] [])) "<colgroup span=\"0\"></colgroup>") "colgroup passes through zero span without validation")
    (assert (= (h/render (h/colgroup [(h/attr "span" "1000")] [])) "<colgroup span=\"1000\"></colgroup>") "colgroup passes through maximum span")
    (assert (= (h/render (h/dataEl [(h/valueAttr "0")] [(h/text "zero")])) "<data value=\"0\">zero</data>") "dataEl preserves zero")
    (assert (= (h/render (h/dataEl [(h/valueAttr "9223372036854775807")] [])) "<data value=\"9223372036854775807\"></data>") "dataEl preserves Int64 max as text")
    (assert (= (h/render (h/datalist [] [(h/option [] [])])) "<datalist><option></option></datalist>") "datalist accepts an empty option")
    (assert (= (h/render (h/dfn [] [(h/text "<&>")])) "<dfn>&lt;&amp;&gt;</dfn>") "dfn escapes text children")
    (assert (= (h/render (h/fieldset [(h/flag "disabled")] [])) "<fieldset disabled></fieldset>") "fieldset renders a boolean flag with no value")
    (assert (= (h/render (h/figcaption [] [(h/text "<&>")])) "<figcaption>&lt;&amp;&gt;</figcaption>") "figcaption escapes text children")
    (assert (= (h/render (h/hgroup [] [(h/h1 [] [])])) "<hgroup><h1></h1></hgroup>") "hgroup accepts an empty heading")
    (assert (= (h/render (h/iframe [(h/src "")] [])) "<iframe src=\"\"></iframe>") "iframe preserves empty src and omits title")
    (assert (= (h/render (h/kbd [] [(h/text "<&>")])) "<kbd>&lt;&amp;&gt;</kbd>") "kbd escapes text children")
    (assert (= (h/render (h/legend [] [(h/text "<&>")])) "<legend>&lt;&amp;&gt;</legend>") "legend escapes text children")
    (assert (= (h/render (h/menu [] [(h/li [] [])])) "<menu><li></li></menu>") "menu accepts an empty item")
    (assert (= (h/render (h/objectEl [(h/attr "data" "")] [])) "<object data=\"\"></object>") "objectEl preserves empty data with no fallback")
    (assert (= (h/render (h/optgroup [(h/attr "label" "")] [])) "<optgroup label=\"\"></optgroup>") "optgroup preserves an empty label and no options")
    (assert (= (h/render (h/picture [] [(h/source [])])) "<picture><source/></picture>") "picture accepts a source with no attributes")
    (assert (= (h/render (h/samp [] [(h/text "<&>")])) "<samp>&lt;&amp;&gt;</samp>") "samp escapes text children")
    (assert (= (h/render (h/tbody [] [(h/tr [] [])])) "<tbody><tr></tr></tbody>") "tbody accepts an empty row")
    true)

