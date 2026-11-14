(module asl-ui/tests/lowerHtmlTest
  :x [runTests]
  :i [(asl-ui/lowerHtml :a low) (asl-ui/view :a ui) (asl-ui/semTokens :a t) (asl-html/html :a h) (asl-html/css :a c)])

fn html v: ui/View -> String
  (h/render (low/lower (ui/resolve v)))

fn everything -> ui/View
  (ui/stack (t/lg) (ui/stretch)
    [(ui/heading (ui/top) "A") (ui/heading (ui/section) "B") (ui/heading (ui/sub) "C") (ui/text "p")
     (ui/note (t/neutral) "n") (ui/note (t/primary) "n") (ui/note (t/success) "n") (ui/note (t/warn) "n") (ui/note (t/danger) "n")
     (ui/button "Strong" (t/strong) 1) (ui/button "Normal" (t/normal) 2) (ui/button "Weak" (t/weak) 3)
     (ui/field "Name" "v" 4) (ui/toggle "On" true 5) (ui/link "Docs" "/d") (ui/image "Logo" "/l.png")
     (ui/row (t/xs) (ui/start) []) (ui/row (t/sm) (ui/center) []) (ui/row (t/md) (ui/end) []) (ui/row (t/xl) (ui/stretch) [])])

fn attrClasses a: h/Attr -> (List String)
  (match a ((h/attrPair k v) (if (= k "class") (stringSplit v " ") [])) ((h/attrFlag k) []))

fn classesOf node: h/Node -> (List String)
  (match node
    ((h/elemNode tag attrs kids) (listAppend (listFlatMap attrClasses attrs) (listFlatMap classesOf kids)))
    ((h/textNode s) [])
    ((h/fragNode kids) (listFlatMap classesOf kids))
    ((h/rawTextNode tag attrs body) []))

fn styled? css: String name: String -> Bool
  (listAny? (fn [close] (stringContains? css (str "." name close))) ["{" "," "["])

fn varNames css: String -> (List String)
  (map (fn [part] (optionOr (listHead (stringSplit part ")")) "")) (listDrop (stringSplit css "var(--") 1))

fn runTests -> Bool
  (let [(theme (t/defaultTheme))
        (root (c/renderSheet (low/themeRules theme)))
        (kit (c/renderSheet (low/kitRules)))
        (used (classesOf (low/lower (ui/resolve (everything)))))]
    (assert (= (html (ui/text "x < y")) "<p id=\"text0\" class=\"ui-text ui-type-body\">x &lt; y</p>") "text is a paragraph with escaped content")
    (assert (= (html (ui/heading (ui/top) "T")) "<h1 id=\"heading0\" class=\"ui-heading ui-type-display\">T</h1>") "a top heading is h1")
    (assert (= (html (ui/heading (ui/section) "T")) "<h2 id=\"heading0\" class=\"ui-heading ui-type-title\">T</h2>") "a section heading is h2")
    (assert (= (html (ui/heading (ui/sub) "T")) "<h3 id=\"heading0\" class=\"ui-heading ui-type-label\">T</h3>") "a sub heading is h3")
    (assert (= (html (ui/note (t/success) "Saved")) "<p id=\"status0\" role=\"status\" class=\"ui-note ui-tone-success ui-type-body\">Saved</p>") "a note is a status region in its tone")
    (assert (= (html (ui/button "Send" (t/strong) 2)) "<button type=\"button\" id=\"button-send\" class=\"ui-button ui-emphasis-strong ui-type-label\" data-msg=\"2\">Send</button>") "a button is a non-submitting button wired by data-msg")
    (assert (= (html (ui/field "Your name" "A\"da" 1)) "<div class=\"ui-field\"><label for=\"textbox-your-name\" class=\"ui-type-label\">Your name</label><input id=\"textbox-your-name\" type=\"text\" value=\"A&quot;da\" class=\"ui-input ui-type-body\" data-msg-input=\"1\"/></div>") "a field is a label wired to its input by id, with the value escaped")
    (assert (= (html (ui/toggle "News" true 3)) "<button type=\"button\" id=\"switch-news\" role=\"switch\" aria-checked=\"true\" class=\"ui-toggle ui-type-label\" data-msg=\"3\">News</button>") "an on toggle is a checked switch")
    (assert (stringContains? (html (ui/toggle "News" false 3)) "aria-checked=\"false\"") "an off toggle is an unchecked switch")
    (assert (= (html (ui/link "Docs" "/docs?a=1&b=2")) "<a id=\"link-docs\" href=\"/docs?a=1&amp;b=2\" class=\"ui-link ui-type-body\">Docs</a>") "a link is an anchor with an escaped target")
    (assert (= (html (ui/image "Logo" "/l.png")) "<img id=\"image0\" src=\"/l.png\" alt=\"Logo\" class=\"ui-image\"/>") "an image carries its label as alt text")
    (assert (= (html (ui/stack (t/md) (ui/start) [(ui/text "a")])) "<div id=\"group0\" class=\"ui-group ui-stack ui-gap-md ui-align-start\"><p id=\"group0-text0\" class=\"ui-text ui-type-body\">a</p></div>") "a stack is a column group holding its children")
    (assert (= (html (ui/row (t/sm) (ui/end) [])) "<div id=\"group0\" class=\"ui-group ui-row ui-gap-sm ui-align-end\"></div>") "a row is a row group with its gap and alignment")
    (assert (= (html (ui/stack (t/md) (ui/start) [(ui/when false (ui/text "a"))])) "<div id=\"group0\" class=\"ui-group ui-stack ui-gap-md ui-align-start\"></div>") "an absent child renders nothing")
    (assert (= (html (ui/absent)) "") "an absent root renders nothing")
    (assert (= (html (ui/keyed "save" (ui/button "Go" (t/weak) 7))) "<button type=\"button\" id=\"save\" class=\"ui-button ui-emphasis-weak ui-type-label\" data-msg=\"7\">Go</button>") "a keyed widget renders under its key")
    (assert (listAll? (fn [name] (styled? kit name)) used) "every class the lowering emits has a rule in the kit sheet")
    (assert (listContains? used "ui-align-stretch") "the class check covers the widget sample")
    (assert (listAll? (fn [name] (stringContains? root (str "--" name ":"))) (varNames kit)) "every variable the kit sheet reads is defined by the theme rule")
    (assert (listContains? (varNames kit) "tone-danger-on") "the variable check covers tone variables")
    (assert (not (or (stringContains? kit "#") (or (stringContains? kit "px") (stringContains? kit "rem")))) "the kit sheet holds no hex colour and no px or rem length")
    (assert (stringStartsWith? root ":root{--stroke:0.0625rem;--space-xs:0.25rem;--space-sm:0.5rem;--space-md:1.0rem;--space-lg:1.5rem;--space-xl:2.5rem;--radius-sharp:0.0rem;--radius-soft:0.375rem;--radius-pill:62.4375rem;--color-surface:#ffffff;--color-ink:#1a1a1a;") "the theme rule lists stroke, space, radius and colour variables in order")
    (assert (stringContains? root "--tone-danger-fill:#b3261e;--tone-danger-on:#ffffff;") "each tone has a fill and a content variable")
    (assert (stringContains? root "--text-mono-size:0.875rem;--text-mono-line:1.25rem;--text-mono-weight:400;--text-mono-family:ui-monospace,monospace") "each text role has size, line, weight and family variables")
    (assert (stringContains? (c/renderSheet (low/themeRules (with theme :stroke (t/dp 2)))) "--stroke:0.125rem;") "a changed theme changes the variable")
    (assert (= (c/renderSheet (low/sheet theme)) (str root "\n" kit)) "the sheet is the theme rule followed by the kit rules")
    (assert (= (low/lengthCss (t/dp 24)) "1.5rem") "sixteen units make one rem")
    (assert (= (low/colorCss (t/rgb 300 -5 16)) "#ff0010") "a colour is six hex digits with channels clamped")
    (assert (= (low/selector (ui/resolve (ui/button "Send" (t/strong) 2))) "#button-send") "a selector addresses a node by id")
    (assert (match (low/page theme (ui/button "Send" (t/strong) 2)) ((ok node) (= (h/render node) (str "<style>" root "\n" kit "</style>" (html (ui/button "Send" (t/strong) 2))))) ((err found) false)) "a page is the style sheet followed by the lowered view")
    (assert (match (low/page theme (ui/row (t/sm) (ui/start) [(ui/button "Go" (t/strong) 1) (ui/button "Go" (t/strong) 2)])) ((ok node) false) ((err found) (= found [(ui/clash "group0-button-go")]))) "a page with an id clash is an error, not markup")
    true)
