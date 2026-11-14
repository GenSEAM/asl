(module asl-ui/lowerHtml
  :x [lengthCss colorCss themeRules kitRules sheet lower page selector]
  :i [(asl-html/html :a h) (asl-html/css :a c) (asl-ui/semTokens :a t) (asl-ui/view :a ui)])

fn lengthCss l: t/Length -> String
  (match l ((t/dp n) (c/rem (/ (int64ToFloat64 n) 16.0))))

fn hexDigit n: Int64 -> String
  (optionOr (stringSlice "0123456789abcdef" n (+ n 1)) "0")

fn hexPair n: Int64 -> String
  (let [(v (max 0 (min n 255)))] (str (hexDigit (/ v 16)) (hexDigit (mod v 16))))

fn colorCss color: t/Color -> String
  (match color ((t/rgb r g b) (str "#" (hexPair r) (hexPair g) (hexPair b))))

fn family style: t/TextStyle -> String
  (if style.fixedPitch "ui-monospace,monospace" "system-ui,sans-serif")

fn textVars theme: t/Theme role: t/TextRole -> (List c/Decl)
  (let [(style (t/textOf theme role)) (name (str "--text-" (t/textName role)))]
    [(c/decl (str name "-size") (lengthCss style.size))
     (c/decl (str name "-line") (lengthCss style.line))
     (c/decl (str name "-weight") (stringFromInt64 style.weight))
     (c/decl (str name "-family") (family style))])

fn toneVars theme: t/Theme tone: t/Tone -> (List c/Decl)
  [(c/decl (str "--tone-" (t/toneName tone) "-fill") (colorCss (t/colorOf theme (t/fill tone))))
   (c/decl (str "--tone-" (t/toneName tone) "-on") (colorCss (t/colorOf theme (t/onFill tone))))]

fn colorVars theme: t/Theme -> (List c/Decl)
  [(c/decl "--color-surface" (colorCss (t/colorOf theme (t/surface))))
   (c/decl "--color-ink" (colorCss (t/colorOf theme (t/ink))))
   (c/decl "--color-ink-weak" (colorCss (t/colorOf theme (t/inkWeak))))
   (c/decl "--color-border" (colorCss (t/colorOf theme (t/border))))
   (c/decl "--color-link" (colorCss (t/colorOf theme (t/linkInk))))
   (c/decl "--color-selection" (colorCss (t/colorOf theme (t/selection))))
   (c/decl "--color-focus" (colorCss (t/colorOf theme (t/focusRing))))]

fn themeRules theme: t/Theme -> (List c/Rule)
  [(c/rule ":root"
     (listAppend [(c/decl "--stroke" (lengthCss theme.stroke))]
       (listAppend (map (fn [s] (c/decl (str "--space-" (t/spaceName s)) (lengthCss (t/spaceOf theme s)))) (t/allSpaces))
         (listAppend (map (fn [r] (c/decl (str "--radius-" (t/radiusName r)) (lengthCss (t/radiusOf theme r)))) (t/allRadii))
           (listAppend (colorVars theme)
             (listAppend (listFlatMap (fn [tone] (toneVars theme tone)) (t/allTones))
               (listFlatMap (fn [role] (textVars theme role)) (t/allTextRoles))))))))]

fn alignName a: ui/Align -> String
  (match a ((ui/start) "start") ((ui/center) "center") ((ui/end) "end") ((ui/stretch) "stretch"))

fn alignCss a: ui/Align -> String
  (match a ((ui/start) "flex-start") ((ui/center) "center") ((ui/end) "flex-end") ((ui/stretch) "stretch"))

fn typeRule role: t/TextRole -> c/Rule
  (let [(name (str "text-" (t/textName role)))]
    (c/rule (str ".ui-type-" (t/textName role))
      [(c/decl "font-size" (c/cssVar (str name "-size")))
       (c/decl "line-height" (c/cssVar (str name "-line")))
       (c/decl "font-weight" (c/cssVar (str name "-weight")))
       (c/decl "font-family" (c/cssVar (str name "-family")))]))

fn toneRule tone: t/Tone -> c/Rule
  (c/rule (str ".ui-tone-" (t/toneName tone))
    [(c/decl "background" (c/cssVar (str "tone-" (t/toneName tone) "-fill")))
     (c/decl "color" (c/cssVar (str "tone-" (t/toneName tone) "-on")))])

fn control -> (List c/Decl)
  [(c/decl "padding" (str (c/cssVar "space-sm") " " (c/cssVar "space-md")))
   (c/decl "border" (str (c/cssVar "stroke") " solid " (c/cssVar "color-border")))]

fn kitRules -> (List c/Rule)
  (listAppend
    [(c/rule ".ui-group" [(c/decl "display" "flex")])
     (c/rule ".ui-stack" [(c/decl "flex-direction" "column")])
     (c/rule ".ui-row" [(c/decl "flex-direction" "row") (c/decl "flex-wrap" "wrap")])
     (c/ruleFor [".ui-text" ".ui-heading"] [(c/decl "margin" "0") (c/decl "color" (c/cssVar "color-ink"))])
     (c/rule ".ui-note" [(c/decl "margin" "0") (c/decl "padding" (str (c/cssVar "space-sm") " " (c/cssVar "space-md"))) (c/decl "border-radius" (c/cssVar "radius-soft"))])
     (c/rule ".ui-button" (listAppend (control) [(c/decl "border-radius" (c/cssVar "radius-soft")) (c/decl "cursor" "pointer")]))
     (c/rule ".ui-emphasis-strong" [(c/decl "background" (c/cssVar "tone-primary-fill")) (c/decl "color" (c/cssVar "tone-primary-on")) (c/decl "border-color" (c/cssVar "tone-primary-fill"))])
     (c/rule ".ui-emphasis-normal" [(c/decl "background" (c/cssVar "color-surface")) (c/decl "color" (c/cssVar "color-ink"))])
     (c/rule ".ui-emphasis-weak" [(c/decl "background" "transparent") (c/decl "color" (c/cssVar "color-link")) (c/decl "border-color" "transparent")])
     (c/rule ".ui-field" [(c/decl "display" "flex") (c/decl "flex-direction" "column") (c/decl "gap" (c/cssVar "space-xs")) (c/decl "color" (c/cssVar "color-ink"))])
     (c/rule ".ui-input" (listAppend (control) [(c/decl "border-radius" (c/cssVar "radius-soft")) (c/decl "background" (c/cssVar "color-surface")) (c/decl "color" (c/cssVar "color-ink"))]))
     (c/rule ".ui-toggle" (listAppend (control) [(c/decl "border-radius" (c/cssVar "radius-pill")) (c/decl "background" (c/cssVar "tone-neutral-fill")) (c/decl "color" (c/cssVar "tone-neutral-on")) (c/decl "cursor" "pointer")]))
     (c/rule ".ui-toggle[aria-checked=true]" [(c/decl "background" (c/cssVar "tone-primary-fill")) (c/decl "color" (c/cssVar "tone-primary-on"))])
     (c/rule ".ui-link" [(c/decl "color" (c/cssVar "color-link"))])
     (c/rule ".ui-image" [(c/decl "max-width" (c/pct 100)) (c/decl "border-radius" (c/cssVar "radius-sharp"))])
     (c/ruleFor [".ui-button:focus-visible" ".ui-input:focus-visible" ".ui-toggle:focus-visible" ".ui-link:focus-visible"] [(c/decl "outline" (str "calc(" (c/cssVar "stroke") "*2) solid " (c/cssVar "color-focus")))])
     (c/rule "::selection" [(c/decl "background" (c/cssVar "color-selection")) (c/decl "color" (c/cssVar "color-ink"))])]
    (listAppend (map (fn [s] (c/rule (str ".ui-gap-" (t/spaceName s)) [(c/decl "gap" (c/cssVar (str "space-" (t/spaceName s))))])) (t/allSpaces))
      (listAppend (map (fn [a] (c/rule (str ".ui-align-" (alignName a)) [(c/decl "align-items" (alignCss a))])) [(ui/start) (ui/center) (ui/end) (ui/stretch)])
        (listAppend (map toneRule (t/allTones)) (map typeRule (t/allTextRoles))))))

fn sheet theme: t/Theme -> (List c/Rule)
  (listAppend (themeRules theme) (kitRules))

fn selector item: ui/Item -> String
  (str "#" item.id)

fn code msg: Int64 -> String
  (stringFromInt64 msg)

fn groupClass direction: String gap: t/Space align: ui/Align -> h/Attr
  (h/classes ["ui-group" direction (str "ui-gap-" (t/spaceName gap)) (str "ui-align-" (alignName align))])

fn lower item: ui/Item -> h/Node
  (match item.view
    ((ui/text s) (h/p [(h/id item.id) (h/cls "ui-text ui-type-body")] [(h/text s)]))
    ((ui/heading level s)
      (match level
        ((ui/top) (h/h1 [(h/id item.id) (h/cls "ui-heading ui-type-display")] [(h/text s)]))
        ((ui/section) (h/h2 [(h/id item.id) (h/cls "ui-heading ui-type-title")] [(h/text s)]))
        ((ui/sub) (h/h3 [(h/id item.id) (h/cls "ui-heading ui-type-label")] [(h/text s)]))))
    ((ui/note tone s) (h/p [(h/id item.id) (h/role "status") (h/classes ["ui-note" (str "ui-tone-" (t/toneName tone)) "ui-type-body"])] [(h/text s)]))
    ((ui/button label emphasis msg) (h/button [(h/id item.id) (h/classes ["ui-button" (str "ui-emphasis-" (t/emphasisName emphasis)) "ui-type-label"]) (h/data "msg" (code msg))] [(h/text label)]))
    ((ui/field label value msg)
      (h/div [(h/cls "ui-field")]
        [(h/label [(h/attr "for" item.id) (h/cls "ui-type-label")] [(h/text label)])
         (h/input [(h/id item.id) (h/typeAttr "text") (h/valueAttr value) (h/cls "ui-input ui-type-body") (h/data "msg-input" (code msg))])]))
    ((ui/toggle label on msg) (h/button [(h/id item.id) (h/role "switch") (h/aria "checked" (if on "true" "false")) (h/cls "ui-toggle ui-type-label") (h/data "msg" (code msg))] [(h/text label)]))
    ((ui/link label url) (h/a [(h/id item.id) (h/href url) (h/cls "ui-link ui-type-body")] [(h/text label)]))
    ((ui/image label url) (h/img [(h/id item.id) (h/src url) (h/alt label) (h/cls "ui-image")]))
    ((ui/stack gap align kids) (h/div [(h/id item.id) (groupClass "ui-stack" gap align)] (map lower item.kids)))
    ((ui/row gap align kids) (h/div [(h/id item.id) (groupClass "ui-row" gap align)] (map lower item.kids)))
    ((ui/keyed key inner) (h/frag []))
    ((ui/absent) (h/frag [])))

fn page theme: t/Theme v: ui/View -> (Result h/Node (List ui/Problem))
  (match (ui/build v)
    ((ok item) (ok (h/frag [(h/styleSheet (sheet theme)) (lower item)])))
    ((err found) (err found)))
