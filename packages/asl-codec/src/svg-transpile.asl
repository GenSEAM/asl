(module asl-codec/svg-transpile
  :d "Bidirectional ASN <-> SVG Vector Graphics Transpiler & Generative Primitives"
  :x [SvgTranspileResult
      asn-to-svg
      svg-to-asn
      make-vector-card
      make-vector-flowchart
      make-vector-icon
      measure-svg-compaction]
  :i [(core/strings :a s)])

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
      (true
       (let [(asn-tok (estimate-tokens trimmed))
              (s1 (string-replace trimmed "(:svg" "<svg xmlns=\"http://www.w3.org/2000/svg\""))
              (s2 (string-replace s1 "(:defs" "<defs>"))
              (s2b (string-replace s2 "(:def" "<defs>"))
              (s3 (string-replace s2b "(:grad" "<linearGradient"))
              (s4 (string-replace s3 "(:rect" "<rect"))
              (s4b (string-replace s4 "(:rc" "<rect"))
              (s5 (string-replace s4b "(:circle" "<circle"))
              (s5b (string-replace s5 "(:circ" "<circle"))
              (s6 (string-replace s5b "(:path" "<path"))
              (s6b (string-replace s6 "(:p" "<path"))
              (s7 (string-replace s6b "(:text" "<text"))
              (s7b (string-replace s7 "(:txt" "<text"))
              (s8 (string-replace s7b "(:line" "<line"))
              (s8b (string-replace s8 "(:ln" "<line"))
              (s9 (string-replace s8b "(:poly" "<polygon"))
              (s10 (string-replace s9 "(:group" "<g"))
              (s10b (string-replace s10 "(:g" "<g"))
              (s11 (string-replace s10b ":w " "width=\""))
              (s12 (string-replace s11 ":h " "height=\""))
              (s13 (string-replace s12 ":view " "viewBox=\""))
              (s13b (string-replace s13 ":v " "viewBox=\""))
              (s14 (string-replace s13b ":x " "x=\""))
              (s15 (string-replace s14 ":y " "y=\""))
              (s16 (string-replace s15 ":x1 " "x1=\""))
              (s17 (string-replace s16 ":y1 " "y1=\""))
              (s18 (string-replace s17 ":x2 " "x2=\""))
              (s19 (string-replace s18 ":y2 " "y2=\""))
              (s20 (string-replace s19 ":cx " "cx=\""))
              (s21 (string-replace s20 ":cy " "cy=\""))
              (s22 (string-replace s21 ":r " "r=\""))
              (s23 (string-replace s22 ":rx " "rx=\""))
              (s24 (string-replace s23 ":fill " "fill=\""))
              (s24b (string-replace s24 ":f " "fill=\""))
              (s25 (string-replace s24b ":stroke " "stroke=\""))
              (s25b (string-replace s25 ":s " "stroke=\""))
              (s26 (string-replace s25b ":sw " "stroke-width=\""))
              (s27 (string-replace s26 ":op " "opacity=\""))
              (s27b (string-replace s27 ":size " "font-size=\""))
              (s27c (string-replace s27b ":sz " "font-size=\""))
              (s28 (string-replace s27c ":points " "points=\""))
              (s29 (string-replace s28 ":d " "d=\""))
              (s30 (string-replace s29 ":id " "id=\""))
              (s31 (string-replace s30 ")" "/>"))
             (final-svg (if (string-ends-with? s31 "/>")
                            (s/concat (option-or (string-slice s31 0 (- (string-length s31) 2)) "") "</svg>")
                            (s/concat s31 "</svg>")))
             (orig-tok (estimate-tokens final-svg))
             (savings (calc-savings orig-tok asn-tok))]
         (SvgTranspileResult
           :output final-svg
           :original-tokens orig-tok
           :asn-tokens asn-tok
           :savings-percent savings
           :success true))))))

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
      (true
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
             (s19 (string-replace s18 "viewBox=" ":view "))
             (s20 (string-replace s19 "x=" ":x "))
             (s21 (string-replace s20 "y=" ":y "))
             (s22 (string-replace s21 "x1=" ":x1 "))
             (s23 (string-replace s22 "y1=" ":y1 "))
             (s24 (string-replace s23 "x2=" ":x2 "))
             (s25 (string-replace s24 "y2=" ":y2 "))
             (s26 (string-replace s25 "cx=" ":cx "))
             (s27 (string-replace s26 "cy=" ":cy "))
             (s28 (string-replace s27 "r=" ":r "))
             (s29 (string-replace s28 "rx=" ":rx "))
             (s30 (string-replace s29 "fill=" ":fill "))
             (s31 (string-replace s30 "stroke=" ":stroke "))
             (s32 (string-replace s31 "stroke-width=" ":sw "))
             (s33 (string-replace s32 "opacity=" ":op "))
             (s34 (string-replace s33 "points=" ":points "))
             (s35 (string-replace s34 "d=" ":d "))
             (s36 (string-replace s35 "id=" ":id "))
             (s37 (string-replace s36 "/>" ")"))
             (final-asn (string-trim s37))
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
                            (s/concat "(:path :d \"M 160 70 L 220 70\" :stroke \"#64748b\" :w \"2\") ")
                            (s/concat "(:rect :x \"230\" :y \"40\" :w \"140\" :h \"60\" :rx \"8\" :fill \"#1e293b\" :stroke \"#818cf8\") ")
                            (s/concat "(:text :x \"300\" :y \"75\" :fill \"#f8fafc\" :size \"14\" \"" node-b "\") ")
                            (s/concat "(:path :d \"M 370 70 L 430 70\" :stroke \"#64748b\" :w \"2\") ")
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
