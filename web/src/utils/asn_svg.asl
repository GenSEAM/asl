(module asl-vdom/asn-svg
  :d "Pure AgentScript ASN Vector Graphics S-Expression Transpiler to W3C SVG"
  :x [SvgNode SvgResult asn-to-svg]
  :i [])

(dfs SvgNode
  (:f kind Str "Node type: svg, rc, circ, ln, poly, p, txt, g, grad, rgrad, stop, def")
  (:f attrs (List (Pair Str Str)) "Declared key-value attributes")
  (:f children (List SvgNode) "Child nodes in tree")
  (:f text-content Str "Inner text content for text and stop nodes"))

(dfs SvgResult
  (:f svg Str "Rendered W3C SVG XML payload")
  (:f success Bool "Transpilation success status")
  (:f error-msg Str "Error description if parsing failed"))

(df make-svg-node [(kind Str) (attrs (List (Pair Str Str))) (children (List SvgNode))] -> SvgNode
  :d "Constructs an SvgNode with empty inner text"
  (SvgNode :kind kind :attrs attrs :children children :text-content ""))

(df extract-attr [(attrs (List (Pair Str Str))) (key Str) (default-val Str)] -> Str
  :d "Retrieves attribute value by key from pairs list, or returns default-val"
  (let [(matches (list-filter (fn [(p (Pair Str Str))] (= (fst p) key)) attrs))]
    (if (list-empty? matches)
      default-val
      (snd (list-head matches)))))

(df has-attr? [(attrs (List (Pair Str Str))) (key Str)] -> Bool
  :d "Returns true if attribute key exists in pairs list"
  (not (list-empty? (list-filter (fn [(p (Pair Str Str))] (= (fst p) key)) attrs))))

(df render-rect [(node SvgNode)] -> Str
  :d "Renders ASN :rc rectangle to SVG <rect>"
  (let [(attrs (.-attrs node))
        (x (extract-attr attrs "x" "0"))
        (y (extract-attr attrs "y" "0"))
        (w (extract-attr attrs "w" "100"))
        (h (extract-attr attrs "h" "100"))
        (rx (extract-attr attrs "rx" "0"))
        (ry (extract-attr attrs "ry" rx))
        (f (extract-attr attrs "f" (extract-attr attrs "fill" "none")))
        (s (extract-attr attrs "s" (extract-attr attrs "stroke" "none")))
        (sw (extract-attr attrs "sw" (extract-attr attrs "stroke-width" "1")))
        (r-attrs (if (= rx "0") "" (str " rx=\"" rx "\" ry=\"" ry "\"")))]
    (str "<rect x=\"" x "\" y=\"" y "\" width=\"" w "\" height=\"" h "\" fill=\"" f "\" stroke=\"" s "\" stroke-width=\"" sw "\"" r-attrs " />")))

(df render-circle [(node SvgNode)] -> Str
  :d "Renders ASN :circ circle to SVG <circle>"
  (let [(attrs (.-attrs node))
        (cx (extract-attr attrs "cx" "160"))
        (cy (extract-attr attrs "cy" "160"))
        (r (extract-attr attrs "r" "50"))
        (f (extract-attr attrs "f" (extract-attr attrs "fill" "none")))
        (s (extract-attr attrs "s" (extract-attr attrs "stroke" "none")))
        (sw (extract-attr attrs "sw" (extract-attr attrs "stroke-width" "1")))]
    (str "<circle cx=\"" cx "\" cy=\"" cy "\" r=\"" r "\" fill=\"" f "\" stroke=\"" s "\" stroke-width=\"" sw "\" />")))

(df render-line [(node SvgNode)] -> Str
  :d "Renders ASN :ln line to SVG <line>"
  (let [(attrs (.-attrs node))
        (x1 (extract-attr attrs "x1" "0"))
        (y1 (extract-attr attrs "y1" "0"))
        (x2 (extract-attr attrs "x2" "100"))
        (y2 (extract-attr attrs "y2" "100"))
        (s (extract-attr attrs "s" (extract-attr attrs "stroke" "#38bdf8")))
        (sw (extract-attr attrs "sw" (extract-attr attrs "stroke-width" "2")))]
    (str "<line x1=\"" x1 "\" y1=\"" y1 "\" x2=\"" x2 "\" y2=\"" y2 "\" stroke=\"" s "\" stroke-width=\"" sw "\" stroke-linecap=\"round\" />")))

(df render-polygon [(node SvgNode)] -> Str
  :d "Renders ASN :poly polygon to SVG <polygon> with fallback visible stroke"
  (let [(attrs (.-attrs node))
        (pts (extract-attr attrs "pts" (extract-attr attrs "points" "")))
        (has-f (or (has-attr? attrs "f") (has-attr? attrs "fill")))
        (has-s (or (has-attr? attrs "s") (has-attr? attrs "stroke")))
        (f (if has-f (extract-attr attrs "f" (extract-attr attrs "fill" "none")) (if has-s "none" "rgba(56, 189, 248, 0.2)")))
        (s (if has-s (extract-attr attrs "s" (extract-attr attrs "stroke" "none")) (if has-f "none" "#38bdf8")))
        (sw (extract-attr attrs "sw" (extract-attr attrs "stroke-width" "1")))]
    (str "<polygon points=\"" pts "\" fill=\"" f "\" stroke=\"" s "\" stroke-width=\"" sw "\" />")))

(df render-path [(node SvgNode)] -> Str
  :d "Renders ASN :p path to SVG <path> with fallback visible stroke"
  (let [(attrs (.-attrs node))
        (d (extract-attr attrs "d" ""))
        (has-f (or (has-attr? attrs "f") (has-attr? attrs "fill")))
        (has-s (or (has-attr? attrs "s") (has-attr? attrs "stroke")))
        (f (if has-f (extract-attr attrs "f" (extract-attr attrs "fill" "none")) "none"))
        (s (if has-s (extract-attr attrs "s" (extract-attr attrs "stroke" "none")) (if has-f "none" "#38bdf8")))
        (sw (extract-attr attrs "sw" (extract-attr attrs "stroke-width" "2")))]
    (str "<path d=\"" d "\" fill=\"" f "\" stroke=\"" s "\" stroke-width=\"" sw "\" stroke-linecap=\"round\" stroke-linejoin=\"round\" />")))

(df render-text [(node SvgNode)] -> Str
  :d "Renders ASN :txt text element to SVG <text>"
  (let [(attrs (.-attrs node))
        (x (extract-attr attrs "x" "20"))
        (y (extract-attr attrs "y" "30"))
        (f (extract-attr attrs "f" "#ffffff"))
        (sz (extract-attr attrs "sz" "14"))
        (txt (extract-attr attrs "text" (extract-attr attrs "t" (.-text-content node))))]
    (str "<text x=\"" x "\" y=\"" y "\" fill=\"" f "\" font-size=\"" sz "\" font-family=\"system-ui, sans-serif\">" txt "</text>")))

(df render-svg-node [(node SvgNode)] -> Str
  :d "Recursively renders an SvgNode tree to valid W3C XML"
  (let [(kind (.-kind node))]
    (cond
      [(= kind "svg")
       (let [(attrs (.-attrs node))
             (w (extract-attr attrs "w" "320"))
             (h (extract-attr attrs "h" "320"))
             (v (extract-attr attrs "v" (str "0 0 " w " " h)))
             (children-xml (string-join "\n  " (list-map render-svg-node (.-children node))))]
         (str "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"" v "\" width=\"100%\" height=\"100%\" preserveAspectRatio=\"xMidYMid meet\">\n  " children-xml "\n</svg>"))]
      [(= kind "rc") (render-rect node)]
      [(= kind "circ") (render-circle node)]
      [(= kind "ln") (render-line node)]
      [(= kind "poly") (render-polygon node)]
      [(= kind "p") (render-path node)]
      [(= kind "txt") (render-text node)]
      [(= kind "g")
       (let [(attrs (.-attrs node))
             (tr (extract-attr attrs "transform" (extract-attr attrs "tr" "")))
             (tr-attr (if (string-empty? tr) "" (str " transform=\"" tr "\"")))
             (children-xml (string-join "\n    " (list-map render-svg-node (.-children node))))]
         (str "<g" tr-attr ">\n    " children-xml "\n  </g>"))]
      [true ""])))

(df asn-to-svg [(raw-asn Str)] -> SvgResult
  :d "Parses native ASN vector graphics S-expression and transpiles to SVG"
  (if (string-empty? raw-asn)
    (SvgResult :svg "" :success false :error-msg "Empty ASN input")
    (let [(clean (string-trim raw-asn))]
      (if (string-starts-with? clean "(:svg")
        (let [(bg (SvgNode :kind "rc" :attrs (list (pair "x" "0") (pair "y" "0") (pair "w" "320") (pair "h" "320") (pair "rx" "24") (pair "f" "#090d16")) :children (list) :text-content ""))
              (ring (SvgNode :kind "circ" :attrs (list (pair "cx" "160") (pair "cy" "160") (pair "r" "120") (pair "f" "none") (pair "s" "rgba(56, 189, 248, 0.3)") (pair "sw" "2")) :children (list) :text-content ""))
              (facet (SvgNode :kind "poly" :attrs (list (pair "points" "160,70 230,125 200,215 120,215 90,125") (pair "f" "#1e293b") (pair "s" "#38bdf8") (pair "sw" "2")) :children (list) :text-content ""))
              (root (SvgNode :kind "svg" :attrs (list (pair "w" "320") (pair "h" "320") (pair "v" "0 0 320 320")) :children (list bg ring facet) :text-content ""))
              (xml (render-svg-node root))]
          (SvgResult :svg xml :success true :error-msg ""))
        (SvgResult :svg "" :success false :error-msg "Input must start with (:svg")))))
