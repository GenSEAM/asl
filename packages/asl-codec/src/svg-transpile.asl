(module asl-codec/svg-transpile
  :d "Bidirectional ASN <-> SVG Vector Graphics Transpiler & Generative Primitives"
  :x [SvgTranspileResult
      asn-to-svg
      svg-to-asn
      make-vector-card
      make-vector-flowchart
      make-vector-icon
      measure-svg-compaction]
  :i [(asl-text/string :a s)
      (asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)
      (asl-parser/ast :a ast)])

(dfs SvgTranspileResult
  (:f output Str "Transpiled SVG XML or ASN S-expression")
  (:f original-tokens I64 "Token count in verbose XML format")
  (:f asn-tokens I64 "Token count in compact ASN representation")
  (:f savings-percent F64 "Token compaction percentage")
  (:f success Bool "True if parsing succeeded"))

(df estimate-tokens [(text Str)] -> I64
  :d "Deterministic BPE-proxy token count estimation based on byte length."
  (let [(len (string-length text))]
    (cond
      ((<= len 0) 0)
      ((<= len 4) 1)
      (:else (/ (+ len 3) 4)))))

(df calc-savings [(orig I64) (asn I64)] -> F64
  :d "Calculates token compaction percentage."
  (if (<= orig 0)
      0.0
      (let [(diff (- orig asn))]
        (if (<= diff 0)
            0.0
            (/ (* (float-from-int64 diff) 100.0) (float-from-int64 orig))))))

(df strip-quotes [(val Str)] -> Str
  :d "Strips outer double quotes from string values."
  (let [(len (string-length val))]
    (if (and (>= len 2) (and (string-starts-with? val "\"") (string-ends-with? val "\"")))
      (option-or (string-slice val 1 (- len 1)) "")
      val)))

(df norm-tag [(raw Str)] -> Str
  :d "Normalizes ASN tag to canonical SVG XML element name."
  (cond
    ((= raw ":svg") "svg")
    ((or (= raw ":g") (= raw ":group")) "g")
    ((or (= raw ":def") (= raw ":defs")) "defs")
    ((or (= raw ":grad") (= raw ":linearGradient")) "linearGradient")
    ((or (= raw ":rgrad") (= raw ":radialGradient")) "radialGradient")
    ((= raw ":filter") "filter")
    ((= raw ":mask") "mask")
    ((or (= raw ":rc") (= raw ":rect")) "rect")
    ((or (= raw ":circ") (= raw ":circle")) "circle")
    ((or (= raw ":p") (= raw ":path")) "path")
    ((or (= raw ":ln") (= raw ":line")) "line")
    ((or (= raw ":poly") (= raw ":polygon")) "polygon")
    ((or (= raw ":txt") (= raw ":text")) "text")
    ((= raw ":stop") "stop")
    ((= raw ":feGaussianBlur") "feGaussianBlur")
    ((= raw ":feMerge") "feMerge")
    ((= raw ":feMergeNode") "feMergeNode")
    ((= raw ":feOffset") "feOffset")
    ((= raw ":feBlend") "feBlend")
    ((= raw ":feFlood") "feFlood")
    ((= raw ":feComposite") "feComposite")
    ((string-starts-with? raw ":") (option-or (string-slice raw 1 (string-length raw)) raw))
    (:else raw)))

(df norm-attr [(raw Str)] -> Str
  :d "Normalizes ASN attribute keyword to canonical SVG XML attribute name."
  (cond
    ((= raw ":w") "width")
    ((= raw ":h") "height")
    ((or (= raw ":v") (= raw ":view")) "viewBox")
    ((or (= raw ":f") (= raw ":fill")) "fill")
    ((or (= raw ":s") (= raw ":stroke")) "stroke")
    ((or (= raw ":sw") (= raw ":stroke-width")) "stroke-width")
    ((or (= raw ":op") (= raw ":opacity")) "opacity")
    ((or (= raw ":sz") (= raw ":size")) "font-size")
    ((or (= raw ":pts") (= raw ":points")) "points")
    ((or (= raw ":tr") (= raw ":transform")) "transform")
    ((or (= raw ":std-dev") (= raw ":stdDeviation")) "stdDeviation")
    ((or (= raw ":off") (= raw ":offset")) "offset")
    ((or (= raw ":col") (= raw ":stop-color")) "stop-color")
    ((string-starts-with? raw ":") (option-or (string-slice raw 1 (string-length raw)) raw))
    (:else raw)))

(df is-container? [(tag Str)] -> Bool
  :d "Returns true if tag is a container element requiring paired closing tags."
  (or (= tag "svg")
  (or (= tag "g")
  (or (= tag "defs")
  (or (= tag "filter")
  (or (= tag "mask")
  (or (= tag "linearGradient")
  (or (= tag "radialGradient")
  (or (= tag "text")
      (= tag "feMerge"))))))))))

(dfs ParseScan
  (:f attrs Str "Accumulated XML attributes")
  (:f children (List rd/SExpr) "Child S-expression forms")
  (:f text Str "Inner text content")
  (:f pending-key Str "Attribute key awaiting its value"))

(df render-sexpr-node [(expr rd/SExpr)] -> Str
  :d "Recursively renders an SExpr AST node to well-formed SVG XML."
  (mt expr
    ((rd/sexpr-atom v) (strip-quotes v))
    ((rd/sexpr-vect _) "")
    ((rd/sexpr-list items)
     (if (list-empty? items)
       ""
       (let [(head-expr (option-or (list-head items) (rd/make-atom "")))
             (raw-tag (rd/sexpr-head head-expr))
             (tag (norm-tag raw-tag))
             (rest (option-or (list-tail items) (list)))
             (scan (fold (fn [(st ParseScan) (it rd/SExpr)] -> ParseScan
                           (if (string-empty? (.-pending-key st))
                             (mt it
                               ((rd/sexpr-atom v)
                                (if (string-starts-with? v ":")
                                  (ParseScan :attrs (.-attrs st)
                                             :children (.-children st)
                                             :text (.-text st)
                                             :pending-key (norm-attr v))
                                  (ParseScan :attrs (.-attrs st)
                                             :children (.-children st)
                                             :text (s/concat (.-text st) (strip-quotes v))
                                             :pending-key "")))
                               ((rd/sexpr-list _)
                                (ParseScan :attrs (.-attrs st)
                                           :children (list-append (.-children st) (list it))
                                           :text (.-text st)
                                           :pending-key ""))
                               ((rd/sexpr-vect _) st))
                             (let [(key (.-pending-key st))]
                               (mt it
                                 ((rd/sexpr-atom v)
                                  (if (string-starts-with? v ":")
                                    (let [(attr-chunk (s/concat " " key "=\"true\""))]
                                      (ParseScan :attrs (s/concat (.-attrs st) attr-chunk)
                                                 :children (.-children st)
                                                 :text (.-text st)
                                                 :pending-key (norm-attr v)))
                                    (let [(attr-chunk (s/concat " " key "=\"" (strip-quotes v) "\""))]
                                      (ParseScan :attrs (s/concat (.-attrs st) attr-chunk)
                                                 :children (.-children st)
                                                 :text (.-text st)
                                                 :pending-key ""))))
                                 ((rd/sexpr-list _)
                                  (let [(attr-chunk (s/concat " " key "=\"true\""))]
                                    (ParseScan :attrs (s/concat (.-attrs st) attr-chunk)
                                               :children (list-append (.-children st) (list it))
                                               :text (.-text st)
                                               :pending-key "")))
                                 ((rd/sexpr-vect _) st)))))
                         (ParseScan :attrs (if (= tag "svg") " xmlns=\"http://www.w3.org/2000/svg\"" "")
                                    :children (list)
                                    :text ""
                                    :pending-key "")
                         rest))
             (final-attrs (if (string-empty? (.-pending-key scan))
                            (.-attrs scan)
                            (s/concat (.-attrs scan) " " (.-pending-key scan) "=\"true\"")))
             (children-rendered (string-join (list-map (fn [(c rd/SExpr)] -> Str (render-sexpr-node c))
                                                       (.-children scan)) ""))
             (body (s/concat children-rendered (.-text scan)))]
         (if (is-container? tag)
           (s/concat "<" tag final-attrs ">" body "</" tag ">")
           (s/concat "<" tag final-attrs "/>")))))))

(df asn-to-svg [(asn-str Str)] -> SvgTranspileResult
  :d "Transpiles compact ASN vector S-expressions into valid SVG XML."
  (let [(trimmed (string-trim asn-str))]
    (cond
      ((string-empty? trimmed)
       (SvgTranspileResult
         :output "Empty input"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      ((not (or (string-starts-with? trimmed "(:svg")
                (string-starts-with? trimmed "(")))
       (SvgTranspileResult
         :output "Syntax error: invalid ASN vector root"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      (:else
       (let [(toks (lx/tokenize trimmed))
             (forms-res (ast/read-forms toks))]
         (mt forms-res
           ((err _)
            (SvgTranspileResult
              :output "Syntax error: unclosed delimiter"
              :original-tokens 0
              :asn-tokens 0
              :savings-percent 0.0
              :success false))
           ((ok forms)
            (if (list-empty? forms)
              (SvgTranspileResult
                :output "Empty forms"
                :original-tokens 0
                :asn-tokens 0
                :savings-percent 0.0
                :success false)
              (let [(pf (option-or (list-head forms) (ast/PosForm :expr (rd/make-atom "") :line 0 :col 0)))
                    (xml (render-sexpr-node (.-expr pf)))
                    (asn-tok (estimate-tokens trimmed))
                    (orig-tok (estimate-tokens xml))
                    (savings (calc-savings orig-tok asn-tok))]
                (SvgTranspileResult
                  :output xml
                  :original-tokens orig-tok
                  :asn-tokens asn-tok
                  :savings-percent savings
                  :success true))))))))))

(df svg-to-asn [(svg-str Str)] -> SvgTranspileResult
  :d "Parses raw SVG XML into compact ASN vector S-expressions."
  (let [(trimmed (string-trim svg-str))]
    (cond
      ((string-empty? trimmed)
       (SvgTranspileResult
         :output "Empty input"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      ((not (or (string-starts-with? trimmed "<svg")
                (string-starts-with? trimmed "<")))
       (SvgTranspileResult
         :output "Syntax error: invalid SVG XML root"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      (:else
       (let [(orig-tok (estimate-tokens trimmed))
             (s1 (string-replace trimmed "<svg" "(:svg"))
             (s2 (string-replace s1 "xmlns=\"http://www.w3.org/2000/svg\"" ""))
             (s3 (string-replace s2 "<defs>" "(:defs"))
             (s4 (string-replace s3 "</defs>" ")"))
             (s5 (string-replace s4 "<linearGradient" "(:grad"))
             (s6 (string-replace s5 "</linearGradient>" ")"))
             (s7 (string-replace s6 "<rect" "(:rect"))
             (s8 (string-replace s7 "<circle" "(:circle"))
             (s9 (string-replace s8 "<path" "(:path"))
             (s10 (string-replace s9 "<text" "(:text"))
             (s11 (string-replace s10 "<line" "(:line"))
             (s12 (string-replace s11 "<polygon" "(:poly"))
             (s13 (string-replace s12 "<g" "(:group"))
             (s14 (string-replace s13 "</g>" ")"))
             (s15 (string-replace s14 "</text>" ")"))
             (s16 (string-replace s15 "</svg>" ")"))
             (s17 (string-replace s16 "width=" ":w "))
             (s18 (string-replace s17 "height=" ":h "))
             (s19 (string-replace s18 "viewBox=" ":v "))
             (s20 (string-replace s19 "stroke-width=" ":sw "))
             (s21 (string-replace s20 "stroke=" ":s "))
             (s22 (string-replace s21 "x1=" ":x1 "))
             (s23 (string-replace s22 "x2=" ":x2 "))
             (s24 (string-replace s23 "cx=" ":cx "))
             (s25 (string-replace s24 "rx=" ":rx "))
             (s26 (string-replace s25 "x=" ":x "))
             (s27 (string-replace s26 "y1=" ":y1 "))
             (s28 (string-replace s27 "y2=" ":y2 "))
             (s29 (string-replace s28 "cy=" ":cy "))
             (s30 (string-replace s29 "ry=" ":ry "))
             (s31 (string-replace s30 "y=" ":y "))
             (s32 (string-replace s31 "r=" ":r "))
             (s33 (string-replace s32 "fill=" ":f "))
             (s34 (string-replace s33 "opacity=" ":op "))
             (s35 (string-replace s34 "points=" ":pts "))
             (s36 (string-replace s35 "id=" ":id "))
             (s37 (string-replace s36 "d=" ":d "))
             (s38 (string-replace s37 "/>" ")"))
             (final-asn (string-trim s38))
             (asn-tok (estimate-tokens final-asn))
             (savings (calc-savings orig-tok asn-tok))]
         (SvgTranspileResult
           :output final-asn
           :original-tokens orig-tok
           :asn-tokens asn-tok
           :savings-percent savings
           :success true))))))

(df make-vector-card [(title Str) (subtitle Str) (accent-color Str)] -> SvgTranspileResult
  :d "Generates responsive UI card vector graphic with rounded gradient rect and typography."
  (let [(asn-card (s/concat "(:svg :w \"400\" :h \"250\" :view \"0 0 400 250\" "
                            (s/concat "(:defs (:grad :id \"card-g\" :fill \"" accent-color "\")) ")
                            (s/concat "(:rect :x \"0\" :y \"0\" :w \"400\" :h \"250\" :rx \"16\" :fill \"#0f172a\" :stroke \"" accent-color "\") ")
                            (s/concat "(:text :x \"24\" :y \"60\" :fill \"#ffffff\" :size \"22\" \"" title "\") ")
                            (s/concat "(:text :x \"24\" :y \"100\" :fill \"#94a3b8\" :size \"14\" \"" subtitle "\"))")))]
    (asn-to-svg asn-card)))

(df make-vector-flowchart [(node-a Str) (node-b Str) (node-c Str)] -> SvgTranspileResult
  :d "Generates sequential node-and-arrow flowchart vector graphic."
  (let [(asn-flow (s/concat "(:svg :w \"600\" :h \"150\" :view \"0 0 600 150\" "
                            (s/concat "(:rect :x \"20\" :y \"40\" :w \"140\" :h \"60\" :rx \"8\" :fill \"#1e293b\" :stroke \"#38bdf8\") ")
                            (s/concat "(:text :x \"90\" :y \"75\" :fill \"#f8fafc\" :size \"14\" \"" node-a "\") ")
                            (s/concat "(:path :d \"M 160 70 L 220 70\" :stroke \"#64748b\" :stroke-width \"2\") ")
                            (s/concat "(:rect :x \"230\" :y \"40\" :w \"140\" :h \"60\" :rx \"8\" :fill \"#1e293b\" :stroke \"#818cf8\") ")
                            (s/concat "(:text :x \"300\" :y \"75\" :fill \"#f8fafc\" :size \"14\" \"" node-b "\") ")
                            (s/concat "(:path :d \"M 370 70 L 430 70\" :stroke \"#64748b\" :stroke-width \"2\") ")
                            (s/concat "(:rect :x \"440\" :y \"40\" :w \"140\" :h \"60\" :rx \"8\" :fill \"#1e293b\" :stroke \"#34d399\") ")
                            (s/concat "(:text :x \"510\" :y \"75\" :fill \"#f8fafc\" :size \"14\" \"" node-c "\"))")))]
    (asn-to-svg asn-flow)))

(df make-vector-icon [(name Str) (path-d Str) (color Str)] -> SvgTranspileResult
  :d "Generates standalone 24x24 vector icon graphic from path and color."
  (let [(asn-icon (s/concat "(:svg :w \"24\" :h \"24\" :view \"0 0 24 24\" "
                            (s/concat "(:path :d \"" path-d "\" :fill \"" color "\" :id \"" name "\"))")))]
    (asn-to-svg asn-icon)))

(df measure-svg-compaction [(svg-xml Str)] -> SvgTranspileResult
  :d "Computes token delta between raw SVG XML and compact ASN vector representation."
  (let [(asn-res (svg-to-asn svg-xml))]
    asn-res))
