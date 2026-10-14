(module aslSite/tests/siteTest
  :x [runTests]
  :i [(aslSite/ui/html :a h) (aslSite/ui/css :a c) (aslSite/ui/bridge :a b) (aslSite/app/msg :a m) (aslSite/app/update :a u) (aslSite/app/theme :a theme) (aslSite/app/home :a home) (aslSite/app/layout :a l)])

fn ops msg: m/Msg model: Int64 -> String
  (b/encodeOps (pairSecond (u/step msg model)))

fn next msg: m/Msg model: Int64 -> Int64
  (pairFirst (u/step msg model))

fn runTests -> Bool
  (let [(page (h/renderDocument (home/homePage (home/Stats :wasmBytes 240640 :aslLines 900 :bridgeLines 80))))]
    (do
      (assert (= (h/render (h/p [(h/cls "a\"b")] [(h/text "x < y & z")])) "<p class=\"a&quot;b\">x &lt; y &amp; z</p>") "text and attributes are escaped")
      (assert (= (h/render (h/elem "link" [] [(h/text "u")])) "<link>u</link>") "a void name with children renders its children")
      (assert (= (h/render (h/meta [(h/attr "charset" "utf-8")])) "<meta charset=\"utf-8\"/>") "an empty void element self-closes")
      (assert (= (h/render (h/button [(h/flag "disabled")] [])) "<button type=\"button\" disabled></button>") "buttons never submit; flags have no value")
      (assert (= (c/renderRule (c/media "(min-width: 1px)" [(c/rule ".a" [(c/decl "color" (c/tokenVar "ink"))])])) "@media (min-width: 1px){.a{color:var(--ink)}}") "css rules nest in media")
      (assert (stringContains? (theme/stylesheet) ":root[data-theme=light]{--ground:#faf8f9") "light tokens come from the palette table")
      (assert (= (b/encodeOp (b/textOp "#x" "say \"hi\"\nnow")) "(:text \"#x\" \"say \\\"hi\\\"\\nnow\")") "bridge strings are ASN-quoted on one line")
      (assert (= (next (m/toggleTheme) 0) 3) "dark -> explicit light")
      (assert (= (next (m/toggleTheme) 3) 2) "light -> explicit dark")
      (assert (stringContains? (ops (m/toggleTheme) 0) "(:store \"theme\" \"light\")") "toggling stores the choice")
      (assert (= (ops (m/boot) 1) "") "boot with the system theme touches nothing")
      (assert (= (ops (m/boot) 3) "(:attr \"html\" \"data-theme\" \"light\")\n(:attr \"#theme-toggle\" \"aria-pressed\" \"true\")\n") "boot applies a stored theme")
      (assert (= (ops (m/copyInstall) 0) (str "(:copy \"" (home/installLine) "\")\n(:text \"#copy-install\" \"Copied\")\n(:after 1600 5)\n")) "copy schedules its own reset")
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
      true))
