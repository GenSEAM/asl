(module aslVdom/asnSvg :x [SvgNode SvgResult asnToSvg parseAllChildren extractFormsByTag renderCircle renderPath renderPolygon renderRect] :i [])

(schema SvgNode (:f kind Str) (:f attrs (List (pair Str Str))) (:f children (List SvgNode)) (:f textContent Str))

(schema SvgResult (:f svg Str) (:f success Bool) (:f errorMsg Str))

fn extractAttr attrs: (List (Pair Str Str)) key: Str defaultVal: Str -> Str
  (let [(matches (filter (fn [(p (pair Str Str))] (= (pairFirst p) key)) attrs))] (mt (listHead matches) ((some p) (pairSecond p)) ((none) defaultVal)))

fn hasAttr? attrs: (List (Pair Str Str)) key: Str -> Bool
  (not (listEmpty? (filter (fn [(p (pair Str Str))] (= (pairFirst p) key)) attrs)))

fn renderRect node: SvgNode -> Str
  (let [(attrs node.attrs) (x (extractAttr attrs "x" "0")) (y (extractAttr attrs "y" "0")) (w (extractAttr attrs "w" "100")) (h (extractAttr attrs "h" "100")) (rx (extractAttr attrs "rx" "0")) (ry (extractAttr attrs "ry" rx)) (f (extractAttr attrs "f" (extractAttr attrs "fill" "none"))) (s (extractAttr attrs "s" (extractAttr attrs "stroke" "none"))) (sw (extractAttr attrs "sw" (extractAttr attrs "stroke-width" "1"))) (rAttrs (if (= rx "0") "" (str " rx=\"" rx "\" ry=\"" ry "\"")))] (str "<rect x=\"" x "\" y=\"" y "\" width=\"" w "\" height=\"" h "\" fill=\"" f "\" stroke=\"" s "\" stroke-width=\"" sw "\"" rAttrs " />"))

fn renderCircle node: SvgNode -> Str
  (let [(attrs node.attrs) (cx (extractAttr attrs "cx" "160")) (cy (extractAttr attrs "cy" "160")) (r (extractAttr attrs "r" "50")) (f (extractAttr attrs "f" (extractAttr attrs "fill" "none"))) (s (extractAttr attrs "s" (extractAttr attrs "stroke" "none"))) (sw (extractAttr attrs "sw" (extractAttr attrs "stroke-width" "1")))] (str "<circle cx=\"" cx "\" cy=\"" cy "\" r=\"" r "\" fill=\"" f "\" stroke=\"" s "\" stroke-width=\"" sw "\" />"))

fn renderLine node: SvgNode -> Str
  (let [(attrs node.attrs) (x1 (extractAttr attrs "x1" "0")) (y1 (extractAttr attrs "y1" "0")) (x2 (extractAttr attrs "x2" "100")) (y2 (extractAttr attrs "y2" "100")) (s (extractAttr attrs "s" (extractAttr attrs "stroke" "#38bdf8"))) (sw (extractAttr attrs "sw" (extractAttr attrs "stroke-width" "2")))] (str "<line x1=\"" x1 "\" y1=\"" y1 "\" x2=\"" x2 "\" y2=\"" y2 "\" stroke=\"" s "\" stroke-width=\"" sw "\" stroke-linecap=\"round\" />"))

fn renderPolygon node: SvgNode -> Str
  (let [(attrs node.attrs) (pts (extractAttr attrs "pts" (extractAttr attrs "points" ""))) (hasF (or (hasAttr? attrs "f") (hasAttr? attrs "fill"))) (hasS (or (hasAttr? attrs "s") (hasAttr? attrs "stroke"))) (f (if hasF (extractAttr attrs "f" (extractAttr attrs "fill" "none")) (if hasS "none" "rgba(56, 189, 248, 0.2)"))) (s (if hasS (extractAttr attrs "s" (extractAttr attrs "stroke" "none")) (if hasF "none" "#38bdf8"))) (sw (extractAttr attrs "sw" (extractAttr attrs "stroke-width" "1")))] (str "<polygon points=\"" pts "\" fill=\"" f "\" stroke=\"" s "\" stroke-width=\"" sw "\" />"))

fn renderPath node: SvgNode -> Str
  (let [(attrs node.attrs) (d (extractAttr attrs "d" "")) (hasF (or (hasAttr? attrs "f") (hasAttr? attrs "fill"))) (hasS (or (hasAttr? attrs "s") (hasAttr? attrs "stroke"))) (f (if hasF (extractAttr attrs "f" (extractAttr attrs "fill" "none")) "none")) (s (if hasS (extractAttr attrs "s" (extractAttr attrs "stroke" "none")) (if hasF "none" "#38bdf8"))) (sw (extractAttr attrs "sw" (extractAttr attrs "stroke-width" "2")))] (str "<path d=\"" d "\" fill=\"" f "\" stroke=\"" s "\" stroke-width=\"" sw "\" stroke-linecap=\"round\" stroke-linejoin=\"round\" />"))

fn renderText node: SvgNode -> Str
  (let [(attrs node.attrs) (x (extractAttr attrs "x" "20")) (y (extractAttr attrs "y" "30")) (f (extractAttr attrs "f" "#ffffff")) (sz (extractAttr attrs "sz" "14")) (txt (extractAttr attrs "text" (extractAttr attrs "t" node.textContent)))] (str "<text x=\"" x "\" y=\"" y "\" fill=\"" f "\" font-size=\"" sz "\" font-family=\"system-ui, sans-serif\">" txt "</text>"))

fn renderSvgNode node: SvgNode -> Str
  (let [(kind node.kind)]
    (cond
      ((= kind "svg")
        (let [(attrs node.attrs)
              (w (extractAttr attrs "w" "320"))
              (h (extractAttr attrs "h" "320"))
              (v (extractAttr attrs "v" (str "0 0 " w " " h)))
              (childrenXml (stringJoin (map renderSvgNode node.children) "\n  "))]
          (str "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"" v "\" width=\"100%\" height=\"100%\" preserveAspectRatio=\"xMidYMid meet\">\n  " childrenXml "\n</svg>")))
      ((= kind "rc") (renderRect node))
      ((= kind "circ") (renderCircle node))
      ((= kind "ln") (renderLine node))
      ((= kind "poly") (renderPolygon node))
      ((= kind "p") (renderPath node))
      ((= kind "txt") (renderText node))
      ((= kind "g")
        (let [(attrs node.attrs)
              (tr (extractAttr attrs "transform" (extractAttr attrs "tr" "")))
              (trAttr (if (stringEmpty? tr) "" (str " transform=\"" tr "\"")))
              (childrenXml (stringJoin (map renderSvgNode node.children) "\n    "))]
          (str "<g" trAttr ">\n    " childrenXml "\n  </g>")))
      (else "")))

fn extractVal src: Str key: Str -> (Option Str)
  (mt (stringIndexOf src (str key " "))
    ((none) (none))
    ((some idx)
      (let [(klen (stringLength key))
            (start (+ (+ idx klen) 1))
            (tail (stringTrim (optionOr (stringSlice src start (stringLength src)) "")))]
        (if (stringStartsWith? tail "\"")
          (let [(p (stringSplit tail "\""))
                (val (optionOr (listHead (optionOr (listTail p) (list))) ""))]
            (some val))
          (let [(words (stringSplit tail " "))
                (rawVal (optionOr (listHead words) ""))
                (cleanVal (stringReplace (stringReplace (stringReplace rawVal ")" "") "\n" "") "\t" ""))]
            (if (stringEmpty? cleanVal) (none) (some cleanVal)))))))

fn collectAttrs src: Str keys: (List Str) -> (List (Pair Str Str))
  (fold (fn [(acc (List (pair Str Str))) (k Str)] (let [(kClean (if (stringStartsWith? k ":") (optionOr (stringSlice k 1 (stringLength k)) k) k))] (mt (extractVal src k) ((some v) (listAppend acc (list (pair kClean v)))) ((none) acc)))) (list) keys)

fn parseChildChunk chunk: Str kind: Str keys: (List Str) -> SvgNode
  (let [(attrs (collectAttrs chunk keys)) (txt (mt (extractVal chunk ":text") ((some tv) tv) ((none) (mt (extractVal chunk ":t") ((some t2) t2) ((none) "")))))] (SvgNode :kind kind :attrs attrs :children (list) :textContent txt))

fn extractFormsByTag src: Str tagOrPrefix: Str -> (List Str)
  (let [(prefix (if (stringStartsWith? tagOrPrefix "(:") tagOrPrefix (str "(:" tagOrPrefix " ")))] (mt (stringIndexOf src prefix) ((none) (list)) ((some startIdx) (let [(sub (optionOr (stringSlice src startIdx (stringLength src)) ""))] (mt (stringIndexOf sub ")") ((none) (list sub)) ((some endIdx) (let [(chunk (optionOr (stringSlice sub 0 (+ endIdx 1)) sub)) (nextPos (+ startIdx (+ endIdx 1))) (rest (if (>= nextPos (stringLength src)) "" (optionOr (stringSlice src nextPos (stringLength src)) "")))] (listAppend (list chunk) (extractFormsByTag rest prefix)))))))))

fn extractFormBetween src: Str prefix: Str -> (Option Str)
  (let [(forms (extractFormsByTag src prefix))] (listHead forms))

fn parseAllChildren src: Str -> (List SvgNode)
  (let [(rcKeys (list ":x" ":y" ":w" ":h" ":rx" ":ry" ":f" ":fill" ":s" ":stroke" ":sw" ":stroke-width")) (circKeys (list ":cx" ":cy" ":r" ":f" ":fill" ":s" ":stroke" ":sw" ":stroke-width")) (lnKeys (list ":x1" ":y1" ":x2" ":y2" ":s" ":stroke" ":sw" ":stroke-width")) (polyKeys (list ":pts" ":points" ":f" ":fill" ":s" ":stroke" ":sw" ":stroke-width")) (pKeys (list ":d" ":f" ":fill" ":s" ":stroke" ":sw" ":stroke-width")) (txtKeys (list ":x" ":y" ":f" ":fill" ":sz" ":size" ":text" ":t")) (rcForms (extractFormsByTag src "(:rc ")) (rcNodes (map (fn [(f Str)] (parseChildChunk f "rc" rcKeys)) rcForms)) (circForms (extractFormsByTag src "(:circ ")) (circNodes (map (fn [(f Str)] (parseChildChunk f "circ" circKeys)) circForms)) (lnForms (extractFormsByTag src "(:ln ")) (lnNodes (map (fn [(f Str)] (parseChildChunk f "ln" lnKeys)) lnForms)) (polyForms (extractFormsByTag src "(:poly ")) (polyNodes (map (fn [(f Str)] (parseChildChunk f "poly" polyKeys)) polyForms)) (pForms (extractFormsByTag src "(:p ")) (pNodes (map (fn [(f Str)] (parseChildChunk f "p" pKeys)) pForms)) (txtForms (extractFormsByTag src "(:txt ")) (txtNodes (map (fn [(f Str)] (parseChildChunk f "txt" txtKeys)) txtForms))] (listAppend rcNodes (listAppend circNodes (listAppend lnNodes (listAppend polyNodes (listAppend pNodes txtNodes))))))

fn asnToSvg rawAsn: Str -> SvgResult
  (if (stringEmpty? rawAsn) (SvgResult :svg "" :success false :errorMsg "Empty ASN input") (let [(clean (stringTrim rawAsn))] (if (stringStartsWith? clean "(:svg") (let [(wVal (mt (extractVal clean ":w") ((some w) w) ((none) "320"))) (hVal (mt (extractVal clean ":h") ((some h) h) ((none) "320"))) (vVal (mt (extractVal clean ":v") ((some v) v) ((none) (str "0 0 " wVal " " hVal)))) (rootAttrs (list (pair "w" wVal) (pair "h" hVal) (pair "v" vVal))) (children (parseAllChildren clean)) (root (SvgNode :kind "svg" :attrs rootAttrs :children children :textContent "")) (xml (renderSvgNode root))] (SvgResult :svg xml :success true :errorMsg "")) (SvgResult :svg "" :success false :errorMsg "Input must start with (:svg"))))
