(module asl-codec/svg-transpile
  :d "Bidirectional ASN <-> SVG Vector Graphics Transpiler & Generative Primitives"
  :x [SvgTranspileResult
      asn-to-svg
      svg-to-asn
      make-vector-card
      make-vector-flowchart
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
             ;; Normalization from ASN S-expression to SVG tags
             (s1 (string-replace trimmed "(:svg" "<svg xmlns=\"http://www.w3.org/2000/svg\""))
             (s2 (string-replace s1 "(:defs" "<defs>"))
             (s3 (string-replace s2 "(:grad" "<linearGradient"))
             (s4 (string-replace s3 "(:rect" "<rect"))
             (s5 (string-replace s4 "(:circle" "<circle"))
             (s6 (string-replace s5 "(:path" "<path"))
             (s7 (string-replace s6 "(:text" "<text"))
             (s8 (string-replace s7 ":w " "width=\""))
             (s9 (string-replace s8 ":h " "height=\""))
             (s10 (string-replace s9 ":view " "viewBox=\""))
             (s11 (string-replace s10 ":x " "x=\""))
             (s12 (string-replace s11 ":y " "y=\""))
             (s13 (string-replace s12 ":cx " "cx=\""))
             (s14 (string-replace s13 ":cy " "cy=\""))
             (s15 (string-replace s14 ":r " "r=\""))
             (s16 (string-replace s15 ":rx " "rx=\""))
             (s17 (string-replace s16 ":fill " "fill=\""))
             (s18 (string-replace s17 ":stroke " "stroke=\""))
             (s19 (string-replace s18 ":d " "d=\""))
             (s20 (string-replace s19 ":id " "id=\""))
             (s21 (string-replace s20 ")" "/>"))
             ;; Close root svg properly
             (final-svg (if (string-ends-with? s21 "/>")
                            (s/concat (option-or (string-slice s21 0 (- (string-length s21) 2)) "") "</svg>")
                            (s/concat s21 "</svg>")))
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
             ;; Normalization from SVG XML to ASN S-expression
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
             (s11 (string-replace s10 "</text>" ")"))
             (s12 (string-replace s11 "</svg>" ")"))
             (s13 (string-replace s12 "width=" ":w "))
             (s14 (string-replace s13 "height=" ":h "))
             (s15 (string-replace s14 "viewBox=" ":view "))
             (s16 (string-replace s15 "x=" ":x "))
             (s17 (string-replace s16 "y=" ":y "))
             (s18 (string-replace s17 "cx=" ":cx "))
             (s19 (string-replace s18 "cy=" ":cy "))
             (s20 (string-replace s19 "r=" ":r "))
             (s21 (string-replace s20 "rx=" ":rx "))
             (s22 (string-replace s21 "fill=" ":fill "))
             (s23 (string-replace s22 "stroke=" ":stroke "))
             (s24 (string-replace s23 "d=" ":d "))
             (s25 (string-replace s24 "id=" ":id "))
             (s26 (string-replace s25 "/>" ")"))
             (final-asn (string-trim s26))
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

(df measure-svg-compaction [(svg-xml Str)] -> SvgTranspileResult
  :d "Computes token delta between raw SVG XML and compact ASN vector representation."
  (let [(asn-res (svg-to-asn svg-xml))]
    asn-res))
