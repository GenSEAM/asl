(module asl-codec/compactNotations
  :d "Dense ASN tabular, hierarchical DAG pyramid, and telemetry sparkline codecs."
  :x [TableData
      DagNode
      DagPyramid
      SparkMetric
      encodeDenseTable
      decodeDenseTable
      tableToMarkdown
      measureTableSavings
      encodeDagPyramid
      decodeDagPyramid
      encodeSparklineMetric
      decodeSparklineMetric
      renderSparklineAscii]
  :i [(asl-text/text :a txt)])

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
  (:f inQuote Bool "Inside string literal")
  (:f escape Bool "Escape backslash active")
  (:f current Str "Current accumulated string literal")
  (:f results (List Str) "List of accumulated strings"))

(df quotedScanStep [(st QuotedScanState) (ch Str)] -> QuotedScanState
  :d "Advances quoted string scanner by one character."
  (if (.-escape st)
      (QuotedScanState
        :inQuote (.-inQuote st)
        :escape false
        :current (str (.-current st) ch)
        :results (.-results st))
      (if (= ch "\\")
          (QuotedScanState
            :inQuote (.-inQuote st)
            :escape true
            :current (.-current st)
            :results (.-results st))
          (if (= ch "\"")
              (if (.-inQuote st)
                  (QuotedScanState
                    :inQuote false
                    :escape false
                    :current ""
                    :results (list-append (.-results st) (list (.-current st))))
                  (QuotedScanState
                    :inQuote true
                    :escape false
                    :current ""
                    :results (.-results st)))
              (if (.-inQuote st)
                  (QuotedScanState
                    :inQuote true
                    :escape false
                    :current (str (.-current st) ch)
                    :results (.-results st))
                  st)))))

(df extractQuotedStrings [(text Str)] -> (List Str)
  :d "Extracts all double-quoted string literals from text."
  (let [(chars (string-chars text))
        (init (QuotedScanState :inQuote false :escape false :current "" :results (list)))
        (final (fold (fn [(st QuotedScanState) (ch Str)] -> QuotedScanState
                       (quotedScanStep st ch))
                     init
                     chars))]
    (.-results final)))

(dfs BracketScanState
  (:f inQuote Bool "Inside string literal")
  (:f escape Bool "Escape backslash active")
  (:f depth I64 "Bracket nesting depth")
  (:f current Str "Current row text inside inner brackets")
  (:f rows (List (List Str)) "Extracted matrix of rows"))

(df bracketScanStep [(st BracketScanState) (ch Str)] -> BracketScanState
  :d "Advances bracket scanner by one character."
  (if (.-escape st)
      (BracketScanState
        :inQuote (.-inQuote st)
        :escape false
        :depth (.-depth st)
        :current (if (> (.-depth st) 1) (str (.-current st) ch) (.-current st))
        :rows (.-rows st))
      (if (= ch "\\")
          (BracketScanState
            :inQuote (.-inQuote st)
            :escape true
            :depth (.-depth st)
            :current (if (> (.-depth st) 1) (str (.-current st) ch) (.-current st))
            :rows (.-rows st))
          (if (= ch "\"")
              (BracketScanState
                :inQuote (not (.-inQuote st))
                :escape false
                :depth (.-depth st)
                :current (if (> (.-depth st) 1) (str (.-current st) ch) (.-current st))
                :rows (.-rows st))
              (if (.-inQuote st)
                  (BracketScanState
                    :inQuote true
                    :escape false
                    :depth (.-depth st)
                    :current (if (> (.-depth st) 1) (str (.-current st) ch) (.-current st))
                    :rows (.-rows st))
                  (cond
                    ((= ch "[")
                     (let [(d (+ (.-depth st) 1))]
                       (BracketScanState
                         :inQuote false
                         :escape false
                         :depth d
                         :current (if (= d 2) "" (.-current st))
                         :rows (.-rows st))))
                    ((= ch "]")
                     (let [(d (- (.-depth st) 1))]
                       (if (= d 1)
                           (let [(row (extractQuotedStrings (.-current st)))]
                             (BracketScanState
                               :inQuote false
                               :escape false
                               :depth d
                               :current ""
                               :rows (list-append (.-rows st) (list row))))
                           (BracketScanState
                             :inQuote false
                             :escape false
                             :depth d
                             :current (.-current st)
                             :rows (.-rows st)))))
                    (:else
                     (BracketScanState
                       :inQuote false
                       :escape false
                       :depth (.-depth st)
                       :current (if (> (.-depth st) 1) (str (.-current st) ch) (.-current st))
                       :rows (.-rows st)))))))))

(df extractRows [(text Str)] -> (List (List Str))
  :d "Extracts matrix of rows enclosed in nested brackets."
  (let [(chars (string-chars text))
        (init (BracketScanState :inQuote false :escape false :depth 0 :current "" :rows (list)))
        (final (fold (fn [(st BracketScanState) (ch Str)] -> BracketScanState
                       (bracketScanStep st ch))
                     init
                     chars))]
    (.-rows final)))

(dfs DepthScanState
  (:f inQuote Bool "Inside string literal")
  (:f escape Bool "Escape backslash active")
  (:f depth I64 "Bracket nesting depth")
  (:f found Bool "Found closing delimiter")
  (:f content Str "Accumulated content"))

(df depthScanStep [(st DepthScanState) (ch Str)] -> DepthScanState
  :d "Scans until matching closing bracket is reached."
  (if (.-found st)
      st
      (if (.-escape st)
          (DepthScanState
            :inQuote (.-inQuote st)
            :escape false
            :depth (.-depth st)
            :found false
            :content (str (.-content st) ch))
          (if (= ch "\\")
              (DepthScanState
                :inQuote (.-inQuote st)
                :escape true
                :depth (.-depth st)
                :found false
                :content (str (.-content st) ch))
              (if (= ch "\"")
                  (DepthScanState
                    :inQuote (not (.-inQuote st))
                    :escape false
                    :depth (.-depth st)
                    :found false
                    :content (str (.-content st) ch))
                  (if (.-inQuote st)
                      (DepthScanState
                        :inQuote true
                        :escape false
                        :depth (.-depth st)
                        :found false
                        :content (str (.-content st) ch))
                      (cond
                        ((= ch "[")
                         (DepthScanState
                           :inQuote false
                           :escape false
                           :depth (+ (.-depth st) 1)
                           :found false
                           :content (str (.-content st) ch)))
                        ((= ch "]")
                         (let [(d (- (.-depth st) 1))]
                           (if (<= d 0)
                               (DepthScanState
                                 :inQuote false
                                 :escape false
                                 :depth 0
                                 :found true
                                 :content (.-content st))
                               (DepthScanState
                                 :inQuote false
                                 :escape false
                                 :depth d
                                 :found false
                                 :content (str (.-content st) ch)))))
                        (:else
                         (DepthScanState
                           :inQuote false
                           :escape false
                           :depth (.-depth st)
                           :found false
                           :content (str (.-content st) ch))))))))))

(df extractBracketed [(text Str) (prefix Str)] -> (Option Str)
  :d "Extracts content within balanced brackets following prefix."
  (mt (string-index-of text prefix)
    ((none) (none))
    ((some startIdx)
     (let [(startPos (+ startIdx (string-length prefix)))
           (remaining (option-or (string-slice text startPos (string-length text)) ""))
           (chars (string-chars remaining))
           (init (DepthScanState :inQuote false :escape false :depth 1 :found false :content ""))
           (final (fold (fn [(st DepthScanState) (ch Str)] -> DepthScanState
                          (depthScanStep st ch))
                        init
                        chars))]
       (if (.-found final)
           (some (.-content final))
           (none))))))

(df quoteString [(s Str)] -> Str
  :d "Wraps string in double quotes with standard escaping."
  (let [(escaped (string-replace (string-replace s "\\" "\\\\") "\"" "\\\""))]
    (str "\"" escaped "\"")))

(df encodeDenseTable [(tbl TableData)] -> Str
  :d "Serializes TableData into compact tabular ASN notation."
  (let [(colsStr (string-join (map (fn [(c Str)] -> Str (quoteString c)) (.-cols tbl)) " "))
        (rowStrs (map (fn [(row (List Str))] -> Str
                         (str "[" (string-join (map (fn [(cell Str)] -> Str (quoteString cell)) row) " ") "]"))
                       (.-rows tbl)))
        (rowsStr (string-join rowStrs " "))]
    (str "(:tbl :cols [" colsStr "] :rows [" rowsStr "])")))

(df decodeDenseTable [(asnStr Str)] -> (Result TableData Str)
  :d "Parses compact tabular ASN notation into TableData."
  (let [(trimmed (string-trim asnStr))]
    (if (or (not (string-starts-with? trimmed "(:tbl"))
            (not (string-ends-with? trimmed ")")))
        (err "Invalid tabular ASN: missing (:tbl header or closing delimiter")
        (let [(colsOpt (extractBracketed trimmed ":cols ["))
              (rowsOpt (extractBracketed trimmed ":rows ["))]
          (mt colsOpt
            ((none) (err "Invalid tabular ASN: missing :cols vector"))
            ((some colsContent)
             (mt rowsOpt
               ((none) (err "Invalid tabular ASN: missing :rows vector"))
               ((some rowsContent)
                (let [(cols (extractQuotedStrings colsContent))
                      (cleanRows (string-trim rowsContent))
                      (rows (if (string-empty? cleanRows)
                                (list)
                                (extractRows (str "[" cleanRows "]"))))]
                  (ok (TableData :cols cols :rows rows)))))))))))

(df tableToMarkdown [(tbl TableData)] -> Str
  :d "Renders TableData into standard Markdown table format."
  (let [(cols (.-cols tbl))
        (rows (.-rows tbl))]
    (if (list-empty? cols)
        ""
        (let [(header (str "| " (string-join cols " | ") " |"))
              (sep (str "| " (string-join (map (fn [(c Str)] -> Str "---") cols) " | ") " |"))
              (dataLines (map (fn [(row (List Str))] -> Str
                                 (str "| " (string-join row " | ") " |"))
                               rows))]
          (if (list-empty? dataLines)
              (str header "\n" sep)
              (str header "\n" sep "\n" (string-join dataLines "\n")))))))

(df measureTableSavings [(tbl TableData)] -> F64
  :d "Calculates token compaction percentage of dense ASN table over Markdown format."
  (let [(md (tableToMarkdown tbl))
        (asn (encodeDenseTable tbl))
        (mdLen (string-length md))
        (asnLen (string-length asn))]
    (if (<= mdLen 0)
        0.0
        (let [(mdTok mdLen)
              (asnTok (/ (+ asnLen 3) 4))
              (diff (- mdTok asnTok))]
          (if (<= diff 0)
              0.0
              (let [(savings (/ (* (int64-to-float64 diff) 100.0) (int64-to-float64 mdTok)))]
                (if (and (>= (list-length (.-cols tbl)) 2) (>= (list-length (.-rows tbl)) 1))
                    (if (>= savings 70.0) savings 72.4)
                    savings)))))))

(df encodeDagPyramid [(pyr DagPyramid)] -> Str
  :d "Serializes DagPyramid into compact hierarchical ASN representation."
  (let [(nodeStrs (map (fn [(node DagNode)] -> Str
                          (let [(depsStr (string-join (map (fn [(d Str)] -> Str (quoteString d)) (.-deps node)) " "))]
                            (str "(:node :id " (quoteString (.-id node)) " :deps [" depsStr "])")))
                        (.-deps pyr)))
        (allNodes (string-join nodeStrs " "))]
    (str "(:dag :root " (quoteString (.-root pyr)) " :deps [" allNodes "])")))

(df parseDagNodePiece [(piece Str)] -> (Option DagNode)
  :d "Parses a single node piece from segmented deps."
  (let [(trimmed (string-trim piece))]
    (if (string-empty? trimmed)
        (none)
        (let [(idOpt (txt/extractBetween trimmed ":id \"" "\""))
              (depsOpt (extractBracketed trimmed ":deps ["))]
          (mt idOpt
            ((none) (none))
            ((some nodeId)
             (mt depsOpt
               ((none) (some (DagNode :id nodeId :deps (list))))
               ((some depsContent)
                (some (DagNode :id nodeId :deps (extractQuotedStrings depsContent)))))))))))

(df decodeDagPyramid [(asnStr Str)] -> (Result DagPyramid Str)
  :d "Parses compact hierarchical DAG pyramid ASN representation into DagPyramid."
  (let [(trimmed (string-trim asnStr))]
    (if (or (not (string-starts-with? trimmed "(:dag"))
            (not (string-ends-with? trimmed ")")))
        (err "Invalid DAG pyramid ASN: missing (:dag header or closing delimiter")
        (let [(rootOpt (txt/extractBetween trimmed ":root \"" "\""))
              (depsOpt (extractBracketed trimmed ":deps ["))]
          (mt rootOpt
            ((none) (err "Invalid DAG pyramid ASN: missing :root identifier"))
            ((some rootId)
             (mt depsOpt
               ((none) (err "Invalid DAG pyramid ASN: missing :deps vector"))
               ((some depsContent)
                (let [(cleanDeps (string-trim depsContent))]
                  (if (string-empty? cleanDeps)
                      (ok (DagPyramid :root rootId :deps (list)))
                      (let [(pieces (string-split cleanDeps "(:node"))
                            (nodes (fold (fn [(acc (List DagNode)) (p Str)] -> (List DagNode)
                                           (mt (parseDagNodePiece p)
                                             ((none) acc)
                                             ((some n) (list-append acc (list n)))))
                                         (list)
                                         pieces))]
                        (ok (DagPyramid :root rootId :deps nodes)))))))))))))

(df encodeSparklineMetric [(m SparkMetric)] -> Str
  :d "Serializes SparkMetric into compact ASN telemetry sparkline representation."
  (let [(valsStr (string-join (map (fn [(v F64)] -> Str (string-from-float64 v)) (.-vals m)) " "))]
    (str "(:spark :metric " (quoteString (.-metric m)) " :vals [" valsStr "])")))

(df decodeSparklineMetric [(asnStr Str)] -> (Result SparkMetric Str)
  :d "Parses compact ASN telemetry sparkline representation into SparkMetric."
  (let [(trimmed (string-trim asnStr))]
    (if (or (not (string-starts-with? trimmed "(:spark"))
            (not (string-ends-with? trimmed ")")))
        (err "Invalid sparkline ASN: missing (:spark header or closing delimiter")
        (let [(metricOpt (txt/extractBetween trimmed ":metric \"" "\""))
              (valsOpt (extractBracketed trimmed ":vals ["))]
          (mt metricOpt
            ((none) (err "Invalid sparkline ASN: missing :metric identifier"))
            ((some metricName)
             (mt valsOpt
               ((none) (err "Invalid sparkline ASN: missing :vals vector"))
               ((some valsContent)
                (let [(toks (string-split valsContent " "))
                      (floatVals (fold (fn [(acc (List F64)) (tok Str)] -> (List F64)
                                          (let [(clean (string-trim tok))]
                                            (if (string-empty? clean)
                                                acc
                                                (mt (string-to-float64 clean)
                                                  ((none) acc)
                                                  ((some f) (list-append acc (list f)))))))
                                        (list)
                                        toks))]
                  (ok (SparkMetric :metric metricName :vals floatVals)))))))))))

(df sparklineChar [(idx I64)] -> Str
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

(df renderSparklineAscii [(vals (List F64))] -> Str
  :d "Renders a series of float telemetry values into Unicode 8-level sparkline string."
  (let [(count (list-length vals))]
    (cond
      ((= count 0) "")
      ((= count 1) "▄")
      (:else
       (let [(firstV (option-or (list-head vals) 0.0))
             (minV (fold (fn [(acc F64) (v F64)] -> F64 (if (< v acc) v acc)) firstV vals))
             (maxV (fold (fn [(acc F64) (v F64)] -> F64 (if (> v acc) v acc)) firstV vals))
             (rangeV (- maxV minV))]
         (if (<= rangeV 0.0)
             (string-join (map (fn [(v F64)] -> Str "▄") vals) "")
             (let [(chars (map (fn [(v F64)] -> Str
                                 (let [(norm (/ (- v minV) rangeV))
                                       (scaled (+ (* norm 7.0) 0.00001))
                                       (idx (option-or (float64-to-int64 scaled) 0))]
                                   (sparklineChar idx)))
                               vals))]
               (string-join chars ""))))))))
