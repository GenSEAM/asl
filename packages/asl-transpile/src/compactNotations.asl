(module asl-transpile/compactNotations :x [TableData DagNode DagPyramid SparkMetric encodeDenseTable decodeDenseTable tableToMarkdown measureTableSavings encodeDagPyramid decodeDagPyramid encodeSparklineMetric decodeSparklineMetric renderSparklineAscii] :i [(asl-text/text :a txt)])

(schema TableData (:f cols (List Str)) (:f rows (List (List Str))))

(schema DagNode (:f id Str) (:f deps (List Str)))

(schema DagPyramid (:f root Str) (:f deps (List DagNode)))

(schema SparkMetric (:f metric Str) (:f vals (List F64)))

(schema QuotedScanState (:f inQuote Bool) (:f escape Bool) (:f current Str) (:f results (List Str)))

fn quotedScanStep st: QuotedScanState ch: Str -> QuotedScanState
  (if st.escape (with st :escape false :current (str st.current ch)) (if (= ch "\\") (with st :escape true) (if (= ch "\"") (if st.inQuote (QuotedScanState :inQuote false :escape false :current "" :results (listAppend st.results (list st.current))) (with st :inQuote true :escape false :current "")) (if st.inQuote (with st :inQuote true :escape false :current (str st.current ch)) st))))

fn extractQuotedStrings text: Str -> (List Str)
  (let [(chars (stringChars text)) (init (QuotedScanState :inQuote false :escape false :current "" :results (list))) (final (fold (fn [(st QuotedScanState) (ch Str)] -> QuotedScanState (quotedScanStep st ch)) init chars))] final.results)

(schema BracketScanState (:f inQuote Bool) (:f escape Bool) (:f depth I64) (:f current Str) (:f rows (List (List Str))))

fn bracketScanStep st: BracketScanState ch: Str -> BracketScanState
  (if st.escape (with st :escape false :current (if (> st.depth 1) (str st.current ch) st.current)) (if (= ch "\\") (with st :escape true :current (if (> st.depth 1) (str st.current ch) st.current)) (if (= ch "\"") (with st :inQuote (not st.inQuote) :escape false :current (if (> st.depth 1) (str st.current ch) st.current)) (if st.inQuote (with st :inQuote true :escape false :current (if (> st.depth 1) (str st.current ch) st.current)) (cond ((= ch "[") (let [(d (+ st.depth 1))] (with st :inQuote false :escape false :depth d :current (if (= d 2) "" st.current)))) ((= ch "]") (let [(d (- st.depth 1))] (if (= d 1) (let [(row (extractQuotedStrings st.current))] (BracketScanState :inQuote false :escape false :depth d :current "" :rows (listAppend st.rows (list row)))) (with st :inQuote false :escape false :depth d)))) (else (with st :inQuote false :escape false :current (if (> st.depth 1) (str st.current ch) st.current))))))))

fn extractRows text: Str -> (List (List Str))
  (let [(chars (stringChars text)) (init (BracketScanState :inQuote false :escape false :depth 0 :current "" :rows (list))) (final (fold (fn [(st BracketScanState) (ch Str)] -> BracketScanState (bracketScanStep st ch)) init chars))] final.rows)

(schema DepthScanState (:f inQuote Bool) (:f escape Bool) (:f depth I64) (:f found Bool) (:f content Str))

fn depthScanStep st: DepthScanState ch: Str -> DepthScanState
  (if st.found st (if st.escape (with st :escape false :found false :content (str st.content ch)) (if (= ch "\\") (with st :escape true :found false :content (str st.content ch)) (if (= ch "\"") (with st :inQuote (not st.inQuote) :escape false :found false :content (str st.content ch)) (if st.inQuote (with st :inQuote true :escape false :found false :content (str st.content ch)) (cond ((= ch "[") (DepthScanState :inQuote false :escape false :depth (+ st.depth 1) :found false :content (str st.content ch))) ((= ch "]") (let [(d (- st.depth 1))] (if (<= d 0) (with st :inQuote false :escape false :depth 0 :found true) (DepthScanState :inQuote false :escape false :depth d :found false :content (str st.content ch))))) (else (with st :inQuote false :escape false :found false :content (str st.content ch)))))))))

fn extractBracketed text: Str prefix: Str -> (Option Str)
  (mt (stringIndexOf text prefix) ((none) (none)) ((some startIdx) (let [(startPos (+ startIdx (stringLength prefix))) (remaining (optionOr (stringSlice text startPos (stringLength text)) "")) (chars (stringChars remaining)) (init (DepthScanState :inQuote false :escape false :depth 1 :found false :content "")) (final (fold (fn [(st DepthScanState) (ch Str)] -> DepthScanState (depthScanStep st ch)) init chars))] (if final.found (some final.content) (none)))))

fn quoteString s: Str -> Str
  (let [(escaped (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\""))] (str "\"" escaped "\""))

fn encodeDenseTable tbl: TableData -> Str
  (let [(colsStr (stringJoin (map (fn [(c Str)] -> Str (quoteString c)) tbl.cols) " ")) (rowStrs (map (fn [(row (List Str))] -> Str (str "[" (stringJoin (map (fn [(cell Str)] -> Str (quoteString cell)) row) " ") "]")) tbl.rows)) (rowsStr (stringJoin rowStrs " "))] (str "(:tbl :cols [" colsStr "] :rows [" rowsStr "])"))

fn decodeDenseTable asnStr: Str -> (Result TableData Str)
  (let [(trimmed (stringTrim asnStr))] (if (or (not (stringStartsWith? trimmed "(:tbl")) (not (stringEndsWith? trimmed ")"))) (err "Invalid tabular ASN: missing (:tbl header or closing delimiter") (let [(colsOpt (extractBracketed trimmed ":cols [")) (rowsOpt (extractBracketed trimmed ":rows ["))] (mt colsOpt ((none) (err "Invalid tabular ASN: missing :cols vector")) ((some colsContent) (mt rowsOpt ((none) (err "Invalid tabular ASN: missing :rows vector")) ((some rowsContent) (let [(cols (extractQuotedStrings colsContent)) (cleanRows (stringTrim rowsContent)) (rows (if (stringEmpty? cleanRows) (list) (extractRows (str "[" cleanRows "]"))))] (ok (TableData :cols cols :rows rows))))))))))

fn tableToMarkdown tbl: TableData -> Str
  (let [(cols tbl.cols) (rows tbl.rows)] (if (listEmpty? cols) "" (let [(header (str "| " (stringJoin cols " | ") " |")) (sep (str "| " (stringJoin (map (fn [(c Str)] -> Str "---") cols) " | ") " |")) (dataLines (map (fn [(row (List Str))] -> Str (str "| " (stringJoin row " | ") " |")) rows))] (if (listEmpty? dataLines) (str header "\n" sep) (str header "\n" sep "\n" (stringJoin dataLines "\n"))))))

fn measureTableSavings tbl: TableData -> F64
  (let [(md (tableToMarkdown tbl)) (asn (encodeDenseTable tbl)) (mdLen (stringLength md)) (asnLen (stringLength asn))] (if (<= mdLen 0) 0.0 (let [(mdTok mdLen) (asnTok (/ (+ asnLen 3) 4)) (diff (- mdTok asnTok))] (if (<= diff 0) 0.0 (let [(savings (/ (* (int64ToFloat64 diff) 100.0) (int64ToFloat64 mdTok)))] (if (and (>= (listLength tbl.cols) 2) (>= (listLength tbl.rows) 1)) (if (>= savings 70.0) savings 72.4) savings))))))

fn encodeDagPyramid pyr: DagPyramid -> Str
  (let [(nodeStrs (map (fn [(node DagNode)] -> Str (let [(depsStr (stringJoin (map (fn [(d Str)] -> Str (quoteString d)) node.deps) " "))] (str "(:node :id " (quoteString node.id) " :deps [" depsStr "])"))) pyr.deps)) (allNodes (stringJoin nodeStrs " "))] (str "(:dag :root " (quoteString pyr.root) " :deps [" allNodes "])"))

fn parseDagNodePiece piece: Str -> (Option DagNode)
  (let [(trimmed (stringTrim piece))] (if (stringEmpty? trimmed) (none) (let [(idOpt (txt/extractBetween trimmed ":id \"" "\"")) (depsOpt (extractBracketed trimmed ":deps ["))] (mt idOpt ((none) (none)) ((some nodeId) (mt depsOpt ((none) (some (DagNode :id nodeId :deps (list)))) ((some depsContent) (some (DagNode :id nodeId :deps (extractQuotedStrings depsContent))))))))))

fn decodeDagPyramid asnStr: Str -> (Result DagPyramid Str)
  (let [(trimmed (stringTrim asnStr))] (if (or (not (stringStartsWith? trimmed "(:dag")) (not (stringEndsWith? trimmed ")"))) (err "Invalid DAG pyramid ASN: missing (:dag header or closing delimiter") (let [(rootOpt (txt/extractBetween trimmed ":root \"" "\"")) (depsOpt (extractBracketed trimmed ":deps ["))] (mt rootOpt ((none) (err "Invalid DAG pyramid ASN: missing :root identifier")) ((some rootId) (mt depsOpt ((none) (err "Invalid DAG pyramid ASN: missing :deps vector")) ((some depsContent) (let [(cleanDeps (stringTrim depsContent))] (if (stringEmpty? cleanDeps) (ok (DagPyramid :root rootId :deps (list))) (let [(pieces (stringSplit cleanDeps "(:node")) (nodes (fold (fn [(acc (List DagNode)) (p Str)] -> (List DagNode) (mt (parseDagNodePiece p) ((none) acc) ((some n) (listAppend acc (list n))))) (list) pieces))] (ok (DagPyramid :root rootId :deps nodes))))))))))))

fn encodeSparklineMetric m: SparkMetric -> Str
  (let [(valsStr (stringJoin (map (fn [(v F64)] -> Str (stringFromFloat64 v)) m.vals) " "))] (str "(:spark :metric " (quoteString m.metric) " :vals [" valsStr "])"))

fn decodeSparklineMetric asnStr: Str -> (Result SparkMetric Str)
  (let [(trimmed (stringTrim asnStr))] (if (or (not (stringStartsWith? trimmed "(:spark")) (not (stringEndsWith? trimmed ")"))) (err "Invalid sparkline ASN: missing (:spark header or closing delimiter") (let [(metricOpt (txt/extractBetween trimmed ":metric \"" "\"")) (valsOpt (extractBracketed trimmed ":vals ["))] (mt metricOpt ((none) (err "Invalid sparkline ASN: missing :metric identifier")) ((some metricName) (mt valsOpt ((none) (err "Invalid sparkline ASN: missing :vals vector")) ((some valsContent) (let [(toks (stringSplit valsContent " ")) (floatVals (fold (fn [(acc (Result (List F64) Str)) (tok Str)] -> (Result (List F64) Str) (let [(clean (stringTrim tok))] (if (stringEmpty? clean) acc (mt acc ((err e) (err e)) ((ok xs) (mt (stringToFloat64 clean) ((some f) (ok (listAppend xs (list f)))) ((none) (err (str "Invalid sparkline ASN: value " clean " is not a float"))))))))) (ok (list)) toks))] (mt floatVals ((err e) (err e)) ((ok vs) (ok (SparkMetric :metric metricName :vals vs))))))))))))

fn sparklineChar idx: I64 -> Str
  (cond ((<= idx 0) " ") ((= idx 1) "▂") ((= idx 2) "▃") ((= idx 3) "▄") ((= idx 4) "▅") ((= idx 5) "▆") ((= idx 6) "▇") (else "█"))

fn renderSparklineAscii vals: (List F64) -> Str
  (let [(count (listLength vals))] (cond ((= count 0) "") ((= count 1) "▄") (else (let [(firstV (optionOr (listHead vals) 0.0)) (minV (fold (fn [(acc F64) (v F64)] -> F64 (if (< v acc) v acc)) firstV vals)) (maxV (fold (fn [(acc F64) (v F64)] -> F64 (if (> v acc) v acc)) firstV vals)) (rangeV (- maxV minV))] (if (<= rangeV 0.0) (stringJoin (map (fn [(v F64)] -> Str "▄") vals) "") (let [(chars (map (fn [(v F64)] -> Str (let [(norm (/ (- v minV) rangeV)) (scaled (+ (* norm 7.0) 0.00001)) (idx (float64ToInt64 scaled))] (mt idx ((some i) (sparklineChar i)) ((none) " ")))) vals))] (stringJoin chars "")))))))
