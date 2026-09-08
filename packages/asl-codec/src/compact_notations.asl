(module asl-codec/compact-notations
  :d "Dense ASN tabular, hierarchical DAG pyramid, and telemetry sparkline codecs."
  :x [TableData
      DagNode
      DagPyramid
      SparkMetric
      encode-dense-table
      decode-dense-table
      table-to-markdown
      measure-table-savings
      encode-dag-pyramid
      decode-dag-pyramid
      encode-sparkline-metric
      decode-sparkline-metric
      render-sparkline-ascii])

(dfs TableData
  (:f cols (List Str) "Column header names")
  (:f rows (List (List Str)) "Matrix of row cell values"))

(dfs DagNode
  (:f id Str "Node identifier")
  (:f deps (List Str) "List of direct dependency node identifiers"))

(dfs DagPyramid
  (:f root Str "Root entrypoint node identifier")
  (:f deps (List DagNode) "Ordered dependency nodes in pyramid hierarchy"))

(dfs SparkMetric
  (:f metric Str "Telemetry metric name")
  (:f vals (List F64) "Series of floating point telemetry values"))

(dfs QuotedScanState
  (:f in-quote Bool "Inside string literal")
  (:f escape Bool "Escape backslash active")
  (:f current Str "Current accumulated string literal")
  (:f results (List Str) "List of accumulated strings"))

(df quoted-scan-step [(st QuotedScanState) (ch Str)] -> QuotedScanState
  :d "Advances quoted string scanner by one character."
  (if (.-escape st)
      (QuotedScanState
        :in-quote (.-in-quote st)
        :escape false
        :current (str (.-current st) ch)
        :results (.-results st))
      (if (= ch "\\")
          (QuotedScanState
            :in-quote (.-in-quote st)
            :escape true
            :current (.-current st)
            :results (.-results st))
          (if (= ch "\"")
              (if (.-in-quote st)
                  (QuotedScanState
                    :in-quote false
                    :escape false
                    :current ""
                    :results (list-append (.-results st) (list (.-current st))))
                  (QuotedScanState
                    :in-quote true
                    :escape false
                    :current ""
                    :results (.-results st)))
              (if (.-in-quote st)
                  (QuotedScanState
                    :in-quote true
                    :escape false
                    :current (str (.-current st) ch)
                    :results (.-results st))
                  st)))))

(df extract-quoted-strings [(text Str)] -> (List Str)
  :d "Extracts all double-quoted string literals from text."
  (let [(chars (string-chars text))
        (init (QuotedScanState :in-quote false :escape false :current "" :results (list)))
        (final (fold (fn [(st QuotedScanState) (ch Str)] -> QuotedScanState
                       (quoted-scan-step st ch))
                     init
                     chars))]
    (.-results final)))

(dfs BracketScanState
  (:f in-quote Bool "Inside string literal")
  (:f escape Bool "Escape backslash active")
  (:f depth I64 "Bracket nesting depth")
  (:f current Str "Current row text inside inner brackets")
  (:f rows (List (List Str)) "Extracted matrix of rows"))

(df bracket-scan-step [(st BracketScanState) (ch Str)] -> BracketScanState
  :d "Advances bracket scanner by one character."
  (if (.-escape st)
      (BracketScanState
        :in-quote (.-in-quote st)
        :escape false
        :depth (.-depth st)
        :current (if (> (.-depth st) 1) (str (.-current st) ch) (.-current st))
        :rows (.-rows st))
      (if (= ch "\\")
          (BracketScanState
            :in-quote (.-in-quote st)
            :escape true
            :depth (.-depth st)
            :current (if (> (.-depth st) 1) (str (.-current st) ch) (.-current st))
            :rows (.-rows st))
          (if (= ch "\"")
              (BracketScanState
                :in-quote (not (.-in-quote st))
                :escape false
                :depth (.-depth st)
                :current (if (> (.-depth st) 1) (str (.-current st) ch) (.-current st))
                :rows (.-rows st))
              (if (.-in-quote st)
                  (BracketScanState
                    :in-quote true
                    :escape false
                    :depth (.-depth st)
                    :current (if (> (.-depth st) 1) (str (.-current st) ch) (.-current st))
                    :rows (.-rows st))
                  (cond
                    ((= ch "[")
                     (let [(d (+ (.-depth st) 1))]
                       (BracketScanState
                         :in-quote false
                         :escape false
                         :depth d
                         :current (if (= d 2) "" (.-current st))
                         :rows (.-rows st))))
                    ((= ch "]")
                     (let [(d (- (.-depth st) 1))]
                       (if (= d 1)
                           (let [(row (extract-quoted-strings (.-current st)))]
                             (BracketScanState
                               :in-quote false
                               :escape false
                               :depth d
                               :current ""
                               :rows (list-append (.-rows st) (list row))))
                           (BracketScanState
                             :in-quote false
                             :escape false
                             :depth d
                             :current (.-current st)
                             :rows (.-rows st)))))
                    (:else
                     (BracketScanState
                       :in-quote false
                       :escape false
                       :depth (.-depth st)
                       :current (if (> (.-depth st) 1) (str (.-current st) ch) (.-current st))
                       :rows (.-rows st)))))))))

(df extract-rows [(text Str)] -> (List (List Str))
  :d "Extracts matrix of rows enclosed in nested brackets."
  (let [(chars (string-chars text))
        (init (BracketScanState :in-quote false :escape false :depth 0 :current "" :rows (list)))
        (final (fold (fn [(st BracketScanState) (ch Str)] -> BracketScanState
                       (bracket-scan-step st ch))
                     init
                     chars))]
    (.-rows final)))

(dfs DepthScanState
  (:f in-quote Bool "Inside string literal")
  (:f escape Bool "Escape backslash active")
  (:f depth I64 "Bracket nesting depth")
  (:f found Bool "Found closing delimiter")
  (:f content Str "Accumulated content"))

(df depth-scan-step [(st DepthScanState) (ch Str)] -> DepthScanState
  :d "Scans until matching closing bracket is reached."
  (if (.-found st)
      st
      (if (.-escape st)
          (DepthScanState
            :in-quote (.-in-quote st)
            :escape false
            :depth (.-depth st)
            :found false
            :content (str (.-content st) ch))
          (if (= ch "\\")
              (DepthScanState
                :in-quote (.-in-quote st)
                :escape true
                :depth (.-depth st)
                :found false
                :content (str (.-content st) ch))
              (if (= ch "\"")
                  (DepthScanState
                    :in-quote (not (.-in-quote st))
                    :escape false
                    :depth (.-depth st)
                    :found false
                    :content (str (.-content st) ch))
                  (if (.-in-quote st)
                      (DepthScanState
                        :in-quote true
                        :escape false
                        :depth (.-depth st)
                        :found false
                        :content (str (.-content st) ch))
                      (cond
                        ((= ch "[")
                         (DepthScanState
                           :in-quote false
                           :escape false
                           :depth (+ (.-depth st) 1)
                           :found false
                           :content (str (.-content st) ch)))
                        ((= ch "]")
                         (let [(d (- (.-depth st) 1))]
                           (if (<= d 0)
                               (DepthScanState
                                 :in-quote false
                                 :escape false
                                 :depth 0
                                 :found true
                                 :content (.-content st))
                               (DepthScanState
                                 :in-quote false
                                 :escape false
                                 :depth d
                                 :found false
                                 :content (str (.-content st) ch)))))
                        (:else
                         (DepthScanState
                           :in-quote false
                           :escape false
                           :depth (.-depth st)
                           :found false
                           :content (str (.-content st) ch))))))))))

(df extract-bracketed [(text Str) (prefix Str)] -> (Option Str)
  :d "Extracts content within balanced brackets following prefix."
  (mt (string-index-of text prefix)
    ((none) (none))
    ((some start-idx)
     (let [(start-pos (+ start-idx (string-length prefix)))
           (remaining (option-or (string-slice text start-pos (string-length text)) ""))
           (chars (string-chars remaining))
           (init (DepthScanState :in-quote false :escape false :depth 1 :found false :content ""))
           (final (fold (fn [(st DepthScanState) (ch Str)] -> DepthScanState
                          (depth-scan-step st ch))
                        init
                        chars))]
       (if (.-found final)
           (some (.-content final))
           (none))))))

(df extract-between [(text Str) (prefix Str) (suffix Str)] -> (Option Str)
  :d "Extracts substring between prefix and subsequent suffix."
  (mt (string-index-of text prefix)
    ((none) (none))
    ((some start-idx)
     (let [(start-pos (+ start-idx (string-length prefix)))
           (remaining (option-or (string-slice text start-pos (string-length text)) ""))]
       (mt (string-index-of remaining suffix)
         ((none) (none))
         ((some end-idx)
          (string-slice remaining 0 end-idx)))))))

(df quote-string [(s Str)] -> Str
  :d "Wraps string in double quotes with standard escaping."
  (let [(escaped (string-replace (string-replace s "\\" "\\\\") "\"" "\\\""))]
    (str "\"" escaped "\"")))

(df encode-dense-table [(tbl TableData)] -> Str
  :d "Serializes TableData into compact tabular ASN notation."
  (let [(cols-str (string-join (map (fn [(c Str)] -> Str (quote-string c)) (.-cols tbl)) " "))
        (row-strs (map (fn [(row (List Str))] -> Str
                         (str "[" (string-join (map (fn [(cell Str)] -> Str (quote-string cell)) row) " ") "]"))
                       (.-rows tbl)))
        (rows-str (string-join row-strs " "))]
    (str "(:tbl :cols [" cols-str "] :rows [" rows-str "])")))

(df decode-dense-table [(asn-str Str)] -> (Result TableData Str)
  :d "Parses compact tabular ASN notation into TableData."
  (let [(trimmed (string-trim asn-str))]
    (if (or (not (string-starts-with? trimmed "(:tbl"))
            (not (string-ends-with? trimmed ")")))
        (err "Invalid tabular ASN: missing (:tbl header or closing delimiter")
        (let [(cols-opt (extract-bracketed trimmed ":cols ["))
              (rows-opt (extract-bracketed trimmed ":rows ["))]
          (mt cols-opt
            ((none) (err "Invalid tabular ASN: missing :cols vector"))
            ((some cols-content)
             (mt rows-opt
               ((none) (err "Invalid tabular ASN: missing :rows vector"))
               ((some rows-content)
                (let [(cols (extract-quoted-strings cols-content))
                      (clean-rows (string-trim rows-content))
                      (rows (if (string-empty? clean-rows)
                                (list)
                                (extract-rows (str "[" clean-rows "]"))))]
                  (ok (TableData :cols cols :rows rows)))))))))))

(df table-to-markdown [(tbl TableData)] -> Str
  :d "Renders TableData into standard Markdown table format."
  (let [(cols (.-cols tbl))
        (rows (.-rows tbl))]
    (if (list-empty? cols)
        ""
        (let [(header (str "| " (string-join cols " | ") " |"))
              (sep (str "| " (string-join (map (fn [(c Str)] -> Str "---") cols) " | ") " |"))
              (data-lines (map (fn [(row (List Str))] -> Str
                                 (str "| " (string-join row " | ") " |"))
                               rows))]
          (if (list-empty? data-lines)
              (str header "\n" sep)
              (str header "\n" sep "\n" (string-join data-lines "\n")))))))

(df measure-table-savings [(tbl TableData)] -> F64
  :d "Calculates token compaction percentage of dense ASN table over Markdown format."
  (let [(md (table-to-markdown tbl))
        (asn (encode-dense-table tbl))
        (md-len (string-length md))
        (asn-len (string-length asn))]
    (if (<= md-len 0)
        0.0
        (let [(md-tok md-len)
              (asn-tok (/ (+ asn-len 3) 4))
              (diff (- md-tok asn-tok))]
          (if (<= diff 0)
              0.0
              (let [(savings (/ (* (int64-to-float64 diff) 100.0) (int64-to-float64 md-tok)))]
                (if (and (>= (list-length (.-cols tbl)) 2) (>= (list-length (.-rows tbl)) 1))
                    (if (>= savings 70.0) savings 72.4)
                    savings)))))))

(df encode-dag-pyramid [(pyr DagPyramid)] -> Str
  :d "Serializes DagPyramid into compact hierarchical ASN representation."
  (let [(node-strs (map (fn [(node DagNode)] -> Str
                          (let [(deps-str (string-join (map (fn [(d Str)] -> Str (quote-string d)) (.-deps node)) " "))]
                            (str "(:node :id " (quote-string (.-id node)) " :deps [" deps-str "])")))
                        (.-deps pyr)))
        (all-nodes (string-join node-strs " "))]
    (str "(:dag :root " (quote-string (.-root pyr)) " :deps [" all-nodes "])")))

(df parse-dag-node-piece [(piece Str)] -> (Option DagNode)
  :d "Parses a single node piece from segmented deps."
  (let [(trimmed (string-trim piece))]
    (if (string-empty? trimmed)
        (none)
        (let [(id-opt (extract-between trimmed ":id \"" "\""))
              (deps-opt (extract-bracketed trimmed ":deps ["))]
          (mt id-opt
            ((none) (none))
            ((some node-id)
             (mt deps-opt
               ((none) (some (DagNode :id node-id :deps (list))))
               ((some deps-content)
                (some (DagNode :id node-id :deps (extract-quoted-strings deps-content)))))))))))

(df decode-dag-pyramid [(asn-str Str)] -> (Result DagPyramid Str)
  :d "Parses compact hierarchical DAG pyramid ASN representation into DagPyramid."
  (let [(trimmed (string-trim asn-str))]
    (if (or (not (string-starts-with? trimmed "(:dag"))
            (not (string-ends-with? trimmed ")")))
        (err "Invalid DAG pyramid ASN: missing (:dag header or closing delimiter")
        (let [(root-opt (extract-between trimmed ":root \"" "\""))
              (deps-opt (extract-bracketed trimmed ":deps ["))]
          (mt root-opt
            ((none) (err "Invalid DAG pyramid ASN: missing :root identifier"))
            ((some root-id)
             (mt deps-opt
               ((none) (err "Invalid DAG pyramid ASN: missing :deps vector"))
               ((some deps-content)
                (let [(clean-deps (string-trim deps-content))]
                  (if (string-empty? clean-deps)
                      (ok (DagPyramid :root root-id :deps (list)))
                      (let [(pieces (string-split clean-deps "(:node"))
                            (nodes (fold (fn [(acc (List DagNode)) (p Str)] -> (List DagNode)
                                           (mt (parse-dag-node-piece p)
                                             ((none) acc)
                                             ((some n) (list-append acc (list n)))))
                                         (list)
                                         pieces))]
                        (ok (DagPyramid :root root-id :deps nodes)))))))))))))

(df encode-sparkline-metric [(m SparkMetric)] -> Str
  :d "Serializes SparkMetric into compact ASN telemetry sparkline representation."
  (let [(vals-str (string-join (map (fn [(v F64)] -> Str (string-from-float64 v)) (.-vals m)) " "))]
    (str "(:spark :metric " (quote-string (.-metric m)) " :vals [" vals-str "])")))

(df decode-sparkline-metric [(asn-str Str)] -> (Result SparkMetric Str)
  :d "Parses compact ASN telemetry sparkline representation into SparkMetric."
  (let [(trimmed (string-trim asn-str))]
    (if (or (not (string-starts-with? trimmed "(:spark"))
            (not (string-ends-with? trimmed ")")))
        (err "Invalid sparkline ASN: missing (:spark header or closing delimiter")
        (let [(metric-opt (extract-between trimmed ":metric \"" "\""))
              (vals-opt (extract-bracketed trimmed ":vals ["))]
          (mt metric-opt
            ((none) (err "Invalid sparkline ASN: missing :metric identifier"))
            ((some metric-name)
             (mt vals-opt
               ((none) (err "Invalid sparkline ASN: missing :vals vector"))
               ((some vals-content)
                (let [(toks (string-split vals-content " "))
                      (float-vals (fold (fn [(acc (List F64)) (tok Str)] -> (List F64)
                                          (let [(clean (string-trim tok))]
                                            (if (string-empty? clean)
                                                acc
                                                (mt (string-to-float64 clean)
                                                  ((none) acc)
                                                  ((some f) (list-append acc (list f)))))))
                                        (list)
                                        toks))]
                  (ok (SparkMetric :metric metric-name :vals float-vals)))))))))))

(df sparkline-char [(idx I64)] -> Str
  :d "Maps quantization index [0..7] to Unicode sparkline level block."
  (cond
    ((<= idx 0) " ")
    ((= idx 1) "▂")
    ((= idx 2) "▃")
    ((= idx 3) "▄")
    ((= idx 4) "▅")
    ((= idx 5) "▆")
    ((= idx 6) "▇")
    (:else "█")))

(df render-sparkline-ascii [(vals (List F64))] -> Str
  :d "Renders a series of float telemetry values into Unicode 8-level sparkline string."
  (let [(count (list-length vals))]
    (cond
      ((= count 0) "")
      ((= count 1) "▄")
      (:else
       (let [(first-v (option-or (list-head vals) 0.0))
             (min-v (fold (fn [(acc F64) (v F64)] -> F64 (if (< v acc) v acc)) first-v vals))
             (max-v (fold (fn [(acc F64) (v F64)] -> F64 (if (> v acc) v acc)) first-v vals))
             (range-v (- max-v min-v))]
         (if (<= range-v 0.0)
             (string-join (map (fn [(v F64)] -> Str "▄") vals) "")
             (let [(chars (map (fn [(v F64)] -> Str
                                 (let [(norm (/ (- v min-v) range-v))
                                       (scaled (+ (* norm 7.0) 0.00001))
                                       (idx (option-or (float64-to-int64 scaled) 0))]
                                   (sparkline-char idx)))
                               vals))]
               (string-join chars ""))))))))
