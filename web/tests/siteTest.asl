(module aslSite/tests/siteTest
  :x [runTests]
  :i [(asl-html/html :a h) (asl-html/css :a c) (aslSite/ui/bridge :a b) (aslSite/app/msg :a m) (aslSite/app/update :a u) (aslSite/app/theme :a theme) (aslSite/app/home :a home) (aslSite/app/docs :a docs) (aslSite/app/layout :a l)])

fn ops msg: m/Msg model: Int64 -> String
  (b/encodeOps (pairSecond (u/step msg model)))

fn next msg: m/Msg model: Int64 -> Int64
  (pairFirst (u/step msg model))

fn runTests -> Bool
  (let [(page (h/renderDocument (home/homePage (home/Stats :wasmBytes 240640 :aslLines 900 :bridgeLines 80))))
        (docsHtml (h/renderDocument (docs/docsPage)))]
    (do
      (assert (= (h/render (h/p [(h/cls "a\"b")] [(h/text "x < y & z")])) "<p class=\"a&quot;b\">x &lt; y &amp; z</p>") "text and attributes are escaped")
      (assert (= (h/render (h/el "link" [] [(h/text "u")])) "<link>u</link>") "a void name with children renders its children")
      (assert (= (h/render (h/meta [(h/attr "charset" "utf-8")])) "<meta charset=\"utf-8\"/>") "an empty void element self-closes")
      (assert (= (h/render (h/button [(h/flag "disabled")] [])) "<button type=\"button\" disabled></button>") "buttons never submit; flags have no value")
      (assert (= (c/renderRule (c/media "(min-width: 1px)" [(c/rule ".a" [(c/decl "color" (c/cssVar "ink"))])])) "@media (min-width: 1px){.a{color:var(--ink)}}") "css rules nest in media")
      (assert (stringContains? (theme/stylesheet) ":root[data-theme=light]{--ground:#faf8f9") "light tokens come from the palette table")
      (assert (= (b/encodeOp (b/textOp "#x" "say \"hi\"\nnow")) "(:text \"#x\" \"say \\\"hi\\\"\\nnow\")") "bridge strings are ASN-quoted on one line")
      (assert (= (next (m/toggleTheme) 0) 3) "dark -> explicit light")
      (assert (= (next (m/toggleTheme) 3) 2) "light -> explicit dark")
      (assert (stringContains? (ops (m/toggleTheme) 0) "(:store \"theme\" \"light\")") "toggling stores the choice")
      (assert (= (ops (m/boot) 1) "") "boot with the system theme touches nothing")
      (assert (= (ops (m/boot) 3) "(:attr \"html\" \"data-theme\" \"light\")\n(:attr \"#theme-toggle\" \"aria-pressed\" \"true\")\n") "boot applies a stored theme")
      (assert (= (ops (m/copyBatch) 0) (str "(:copy \"" (home/batchLine) "\")\n(:text \"#copy-batch\" \"Copied\")\n(:after 1600 5)\n")) "copy schedules its own reset")
      (assert (= (m/msgCode (m/msgOf 3)) 0) "the retired install-copy code is unknown")
      (assert (not (stringContains? page "copy-install")) "no page element or handler for an install command")
      (assert (= (m/msgCode (m/msgOf 4)) 4) "message codes round-trip")
      (assert (= (next (m/unknown) 7) 7) "an unknown message keeps the model")
      (assert (= (u/formatMs 1234567) "1.23 ms") "nanoseconds format as milliseconds")
      (assert (stringStartsWith? page "<!doctype html><html lang=\"en\">") "a document starts with its doctype")
      (assert (stringContains? page "data-msg=\"2\"") "the theme toggle is wired to its message")
      (assert (stringContains? page "235 KB") "stats reach the proof section")
      (assert (not (stringContains? page "<script>")) "no inline script")
      (assert (= (l/routePath (l/post "x")) "/blog/x") "post routes")
      (assert (stringContains? (theme/stylesheet) ".hero-grid{display:grid;grid-template-columns:minmax(0,1fr)") "the hero column cannot grow past the viewport on phones")
      (assert (stringContains? page "class=\"cham small\"") "the chameleon marks the top bar")
      (assert (stringContains? (theme/stylesheet) ".cell{background:var(--surface);padding:1.75rem;display:grid;grid-template-columns:minmax(0,1fr)") "a long frame scrolls inside its cell instead of widening the page")
      (assert (stringContains? page "Not released") "the landing page states the release status")
      (assert (not (or (stringContains? page "curl -fsSL") (stringContains? docsHtml "curl -fsSL"))) "no page offers an install command that does not work")
      (assert (stringContains? page "people building coding agents") "the landing page names its audience")
      (assert (and (stringContains? page ">51<") (and (stringContains? page ">30<") (stringContains? page ">18<"))) "the token example shows the pretty, minified and positional counts")
      (assert (stringContains? page "ERR_UNBALANCED") "the balance error is the code the checker prints")
      (assert (not (or (stringContains? page "ERR_READ_UNBALANCED") (stringContains? page "ERR_EFFECT_UNMARKED"))) "the landing page names no error code the checker does not emit")
      (assert (not (or (stringContains? page "without repair loops") (stringContains? page "a third of the tokens"))) "no unmeasured headline")
      (assert (not (or (stringContains? docsHtml "asl-host") (stringContains? docsHtml "ERR_EFFECT_UNMARKED"))) "the docs name no absent binary and no unenforced check")
      (assert (stringContains? docsHtml "asl test fileTest.asl") "the docs verify with asl check and asl test")
      true))
