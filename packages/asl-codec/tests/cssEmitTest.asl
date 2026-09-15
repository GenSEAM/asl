(module asl-codec/cssEmitTest
  :d "Unit verification test suite for pure ASL CSS emitter"
  :x [testCssEmitVariables
      testCssEmitRules
      testCssEmitMinified
      testCssEmitMedia
      testCssEmitRoundtrip
      testCssEmitRefutations
      runTests]
  :i [(asl-codec/cssEmit :a ce)
      (asl-codec/cssCascade :a cascade)])

(df testCssEmitVariables [] -> Bool
  :d "Verifies rendering of CSS custom properties in :root selector."
  (let [(vars (list (pair "primary" "#007acc") (pair "--bg" "#ffffff") (pair ":font-family" "sans-serif")))
        (cssOut (ce/renderCssVariables vars false))
        (cssMin (ce/renderCssVariables vars true))]
    (assert (string-contains? cssOut ":root {") "contains :root {")
    (assert (string-contains? cssOut "--primary: #007acc;") "prefixes -- on bare variable name")
    (assert (string-contains? cssOut "--bg: #ffffff;") "preserves existing -- prefix")
    (assert (string-contains? cssOut "--font-family: sans-serif;") "strips colon and prefixes --")
    (assert (string-contains? cssMin ":root{--primary:#007acc;--bg:#ffffff;--font-family:sans-serif}") "minified root variables")
    true))

(df testCssEmitRules [] -> Bool
  :d "Verifies rendering of selector rules with properties and !important flags."
  (let [(p1 (cascade/CssProperty :name "color" :value "#333" :important false))
        (p2 (cascade/CssProperty :name "margin" :value "0" :important true))
        (spec (cascade/calcSpecificity "body.dark"))
        (rule (cascade/CssRule :selector "body.dark" :specificity spec :properties (list p1 p2) :sourceOrder 0))
        (outPretty (ce/renderCssRule rule false))
        (outMin (ce/renderCssRule rule true))]
    (assert (string-contains? outPretty "body.dark {") "pretty rule selector")
    (assert (string-contains? outPretty "color: #333;") "pretty prop without important")
    (assert (string-contains? outPretty "margin: 0 !important;") "pretty prop with important")
    (assert (= outMin "body.dark{color:#333;margin:0!important}") "minified rule compact")
    true))

(df testCssEmitMinified [] -> Bool
  :d "Verifies minification eliminates newlines and spaces around braces."
  (let [(p (cascade/CssProperty :name "display" :value "flex" :important false))
        (rule (cascade/CssRule :selector ".container" :specificity (cascade/calcSpecificity ".container") :properties (list p) :sourceOrder 0))
        (outMin (ce/renderCssRule rule true))]
    (refute (string-contains? outMin "\n") "minified contains no newlines")
    (refute (string-contains? outMin " {") "no space before opening brace")
    (refute (string-contains? outMin "{ ") "no space after opening brace")
    (refute (string-contains? outMin ";}") "no trailing semicolon before closing brace")
    (assert (= outMin ".container{display:flex}") "exact minified rule output")
    true))

(df testCssEmitMedia [] -> Bool
  :d "Verifies media block query rendering with nested rules."
  (let [(p (cascade/CssProperty :name "font-size" :value "14px" :important false))
        (rule (cascade/CssRule :selector "p" :specificity (cascade/calcSpecificity "p") :properties (list p) :sourceOrder 0))
        (outPretty (ce/renderMediaBlock "(max-width: 600px)" (list rule) false))
        (outMin (ce/renderMediaBlock "(max-width: 600px)" (list rule) true))]
    (assert (string-contains? outPretty "@media (max-width: 600px) {") "media header pretty")
    (assert (string-contains? outPretty "p {") "nested rule pretty")
    (assert (= outMin "@media (max-width: 600px){p{font-size:14px}}") "media compact minified")
    true))

(df testCssEmitRoundtrip [] -> Bool
  :d "Verifies emitted CSS parses cleanly back through parseCssRules."
  (let [(astPayload "(:styles :vars [(:primary \"#007acc\")] :rules [(:rule :selector \"h1\" :props [(:color \"#111\") (:margin \"0\")]) (:rule :selector \".btn\" :props [(:padding \"8px 16px\")])])")
        (emitted (ce/asnToCssStr astPayload false))
        (parsedRules (cascade/parseCssRules emitted))]
    (assert (> (list-length parsedRules) 0) "parsed rules non-empty")
    (let [(h1Rule (filter (fn [(r cascade/CssRule)] -> Bool (= (.-selector r) "h1")) parsedRules))]
      (assert (= (list-length h1Rule) 1) "h1 rule parsed back")
      (let [(r (option-or (list-head h1Rule) (cascade/CssRule :selector "" :specificity (cascade/calcSpecificity "") :properties (list) :sourceOrder 0)))]
        (assert (= (list-length (.-properties r)) 2) "h1 has 2 properties")
        true))))

(df testCssEmitRefutations [] -> Bool
  :d "Dual-polarity refutations for CSS emission."
  (let [(vars (list (pair "raw" "10px")))
        (renderedVars (ce/renderCssVariables vars true))
        (emptyRuleset (ce/asnToCssStr "(:styles :rules [])" false))
        (emptyRule (ce/renderCssRule (cascade/CssRule :selector "div" :specificity (cascade/calcSpecificity "div") :properties (list) :sourceOrder 0) true))]
    (refute (string-contains? renderedVars "{raw:") "variable must not lack -- prefix")
    (assert (string-contains? renderedVars "--raw:10px") "variable must have -- prefix")
    (assert (= emptyRuleset "") "empty ruleset emits empty string without crashing")
    (assert (= emptyRule "div{}") "empty rule emits selector with braces without crashing")
    (refute (string-contains? emptyRule "null") "empty rule must not produce null")
    true))

(df runTests [] -> Bool
  :d "Runs all CSS emitter unit tests."
  (do
    (assert (testCssEmitVariables) "testCssEmitVariables")
    (assert (testCssEmitRules) "testCssEmitRules")
    (assert (testCssEmitMinified) "testCssEmitMinified")
    (assert (testCssEmitMedia) "testCssEmitMedia")
    (assert (testCssEmitRoundtrip) "testCssEmitRoundtrip")
    (assert (testCssEmitRefutations) "testCssEmitRefutations")
    true))
