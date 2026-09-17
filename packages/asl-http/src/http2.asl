(module asl-http/http2
  :d "Pure AgentScript HTTP/2 Binary Framing Codec and HPACK Compression Engine"
  :x [Http2Frame
      HpackTable
      makeHttp2Frame
      encodeHttp2Frame
      decodeHttp2Frame
      makeHpackTable
      encodeHpack
      decodeHpack]
  :i [(asl-http/http11 :a http)])

(dfs Http2Frame
  (:f frameType Int64)
  (:f flags Int64)
  (:f streamId Int64)
  (:f payload String))

(dfs HpackTable
  (:f maxSize Int64)
  (:f currentSize Int64)
  (:f entries (List (Pair String String))))

(df makeHttp2Frame [(frameType Int64) (flags Int64) (streamId Int64) (payload String)] -> Http2Frame
  :d "Constructs Http2Frame record"
  (Http2Frame :frameType frameType :flags flags :streamId streamId :payload payload))

(df encodeHttp2Frame [(frame Http2Frame)] -> String
  :d "Encodes Http2Frame into structured wire frame representation"
  (str "H2F:" (string-from-int64 (string-length (.-payload frame)))
       ":" (string-from-int64 (.-frameType frame))
       ":" (string-from-int64 (.-flags frame))
       ":" (string-from-int64 (.-streamId frame))
       ":" (.-payload frame)))

(df findNthColon [(s String) (pos Int64) (remaining Int64)] -> (Option Int64)
  :d "Finds the index of the Nth colon character"
  (if (<= remaining 0)
    (some pos)
    (let [(sub (option-or (string-slice s pos (string-length s)) ""))
          (idx (string-index-of sub ":"))]
      (mt idx
        ((some off) (findNthColon s (+ (+ pos off) 1) (- remaining 1)))
        ((none) (none))))))

(df decodeHttp2Frame [(raw String)] -> (Result Http2Frame String)
  :d "Decodes wire representation into Http2Frame"
  (if (or (string-empty? raw) (not (string-starts-with? raw "H2F:")))
    (err "ERR_H2_TRUNCATED_FRAME")
    (let [(fifthColonOpt (findNthColon raw 0 5))]
      (mt fifthColonOpt
        ((none) (err "ERR_H2_TRUNCATED_FRAME"))
        ((some headerEnd)
         (let [(headerPart (option-or (string-slice raw 0 (- headerEnd 1)) ""))
               (payload (option-or (string-slice raw headerEnd (string-length raw)) ""))
               (tokens (string-split headerPart ":"))]
           (if (< (list-length tokens) 5)
             (err "ERR_H2_INVALID_HEADER")
             (let [(lenStr (option-or (list-head (option-or (list-tail tokens) (list))) ""))
                   (typeStr (option-or (list-head (option-or (list-tail (option-or (list-tail tokens) (list))) (list))) ""))
                   (flagsStr (option-or (list-head (option-or (list-tail (option-or (list-tail (option-or (list-tail tokens) (list))) (list))) (list))) ""))
                   (streamStr (option-or (list-head (option-or (list-tail (option-or (list-tail (option-or (list-tail (option-or (list-tail tokens) (list))) (list))) (list))) (list))) ""))
                   (len (option-or (string-to-int64 lenStr) -1))
                   (fType (option-or (string-to-int64 typeStr) -1))
                   (flags (option-or (string-to-int64 flagsStr) -1))
                   (streamId (option-or (string-to-int64 streamStr) -1))]
               (if (or (or (< len 0) (< fType 0)) (or (< flags 0) (< streamId 0)))
                 (err "ERR_H2_INVALID_HEADER_FIELDS")
                 (if (not (= (string-length payload) len))
                   (err "ERR_H2_FRAME_LENGTH_MISMATCH")
                   (ok (Http2Frame :frameType fType :flags flags :streamId streamId :payload payload))))))))))))

(df makeHpackTable [(maxSize Int64)] -> HpackTable
  :d "Constructs dynamic HPACK table with specified memory size ceiling"
  (HpackTable :maxSize maxSize :currentSize 0 :entries (list)))

(df formatHpackLines [(entries (List (Pair String String)))] -> String
  :d "Serializes header entries into HPACK line representations"
  (if (list-empty? entries)
    ""
    (let [(p (option-or (list-head entries) (pair "" "")))
          (line (str (fst p) "=" (snd p) "\n"))
          (rest (formatHpackLines (option-or (list-tail entries) (list))))]
      (str line rest))))

(df encodeHpack [(tbl HpackTable) (headers http/HttpHeaders)] -> (Pair HpackTable String)
  :d "Compresses HttpHeaders into HPACK wire block and updates table state"
  (let [(entries (.-entries headers))
        (encodedPayload (str "HPACK:" (string-from-int64 (list-length entries)) "\n"
                             (formatHpackLines entries)))
        (newTbl (HpackTable :maxSize (.-maxSize tbl)
                            :currentSize (+ (.-currentSize tbl) (string-length encodedPayload))
                            :entries entries))]
    (pair newTbl encodedPayload)))

(df parseHpackLine [(line String)] -> (Option (Pair String String))
  :d "Parses key=value HPACK entry"
  (let [(eqPos (string-index-of line "="))]
    (mt eqPos
      ((some idx)
       (let [(k (option-or (string-slice line 0 idx) ""))
             (v (option-or (string-slice line (+ idx 1) (string-length line)) ""))]
         (some (pair k v))))
      ((none) (none)))))

(df parseHpackLinesLoop [(lines (List String)) (acc (List (Pair String String)))] -> (List (Pair String String))
  :d "Recursively parses HPACK lines into header list"
  (if (list-empty? lines)
    (list-reverse acc)
    (let [(line (string-trim (option-or (list-head lines) "")))]
      (if (string-empty? line)
        (parseHpackLinesLoop (option-or (list-tail lines) (list)) acc)
        (let [(pOpt (parseHpackLine line))]
          (mt pOpt
            ((some p) (parseHpackLinesLoop (option-or (list-tail lines) (list)) (list-cons p acc)))
            ((none) (parseHpackLinesLoop (option-or (list-tail lines) (list)) acc))))))))

(df decodeHpack [(tbl HpackTable) (wireBlock String)] -> (Result http/HttpHeaders String)
  :d "Decompresses HPACK wire block into HttpHeaders"
  (if (not (string-starts-with? wireBlock "HPACK:"))
    (err "ERR_HPACK_INVALID_HEADER_BLOCK")
    (let [(newlinePos (string-index-of wireBlock "\n"))]
      (mt newlinePos
        ((some idx)
         (let [(bodyPart (option-or (string-slice wireBlock (+ idx 1) (string-length wireBlock)) ""))
               (lines (string-split bodyPart "\n"))
               (entries (parseHpackLinesLoop lines (list)))]
           (ok (http/makeHeaders entries))))
        ((none)
         (err "ERR_HPACK_MALFORMED_FORMAT"))))))
