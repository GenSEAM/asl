(module asl-http/http2 :x [Http2Frame HpackTable HpackEntry Http2Stream makeHttp2Frame encodeHttp2Frame decodeHttp2Frame encodeBinaryFrame decodeBinaryFrame makeDataFrame makeHeadersFrame makeSettingsFrame makePingFrame makeRstStreamFrame makeGoawayFrame makeWindowUpdateFrame makeHpackTable hpackTableAdd hpackTableEvict encodeHpack decodeHpack FRAME_DATA FRAME_HEADERS FRAME_PRIORITY FRAME_RST_STREAM FRAME_SETTINGS FRAME_PUSH_PROMISE FRAME_PING FRAME_GOAWAY FRAME_WINDOW_UPDATE FRAME_CONTINUATION FLAG_NONE FLAG_ACK FLAG_END_STREAM FLAG_END_HEADERS FLAG_PADDED FLAG_PRIORITY ERR_NO_ERROR ERR_PROTOCOL_ERROR ERR_INTERNAL_ERROR ERR_FLOW_CONTROL_ERROR ERR_SETTINGS_TIMEOUT ERR_STREAM_CLOSED ERR_FRAME_SIZE_ERROR ERR_REFUSED_STREAM ERR_CANCEL ERR_COMPRESSION_ERROR ERR_CONNECT_ERROR SETTINGS_HEADER_TABLE_SIZE SETTINGS_ENABLE_PUSH SETTINGS_MAX_CONCURRENT_STREAMS SETTINGS_INITIAL_WINDOW_SIZE SETTINGS_MAX_FRAME_SIZE SETTINGS_MAX_HEADER_LIST_SIZE] :i [(asl-http/http11 :a http)])

fn FRAME_DATA -> Int64
  0
fn FRAME_HEADERS -> Int64
  1
fn FRAME_PRIORITY -> Int64
  2
fn FRAME_RST_STREAM -> Int64
  3
fn FRAME_SETTINGS -> Int64
  4
fn FRAME_PUSH_PROMISE -> Int64
  5
fn FRAME_PING -> Int64
  6
fn FRAME_GOAWAY -> Int64
  7
fn FRAME_WINDOW_UPDATE -> Int64
  8
fn FRAME_CONTINUATION -> Int64
  9

fn FLAG_NONE -> Int64
  0
fn FLAG_ACK -> Int64
  1
fn FLAG_END_STREAM -> Int64
  1
fn FLAG_END_HEADERS -> Int64
  4
fn FLAG_PADDED -> Int64
  8
fn FLAG_PRIORITY -> Int64
  32

fn ERR_NO_ERROR -> Int64
  0
fn ERR_PROTOCOL_ERROR -> Int64
  1
fn ERR_INTERNAL_ERROR -> Int64
  2
fn ERR_FLOW_CONTROL_ERROR -> Int64
  3
fn ERR_SETTINGS_TIMEOUT -> Int64
  4
fn ERR_STREAM_CLOSED -> Int64
  5
fn ERR_FRAME_SIZE_ERROR -> Int64
  6
fn ERR_REFUSED_STREAM -> Int64
  7
fn ERR_CANCEL -> Int64
  8
fn ERR_COMPRESSION_ERROR -> Int64
  9
fn ERR_CONNECT_ERROR -> Int64
  10

fn SETTINGS_HEADER_TABLE_SIZE -> Int64
  1
fn SETTINGS_ENABLE_PUSH -> Int64
  2
fn SETTINGS_MAX_CONCURRENT_STREAMS -> Int64
  3
fn SETTINGS_INITIAL_WINDOW_SIZE -> Int64
  4
fn SETTINGS_MAX_FRAME_SIZE -> Int64
  5
fn SETTINGS_MAX_HEADER_LIST_SIZE -> Int64
  6


(schema Http2Frame
  (:f frameType Int64)
  (:f flags Int64)
  (:f streamId Int64)
  (:f length Int64)
  (:f payload String))

(schema HpackEntry
  (:f name String)
  (:f value String)
  (:f size Int64))

(schema HpackTable
  (:f maxSize Int64)
  (:f currentSize Int64)
  (:f entries (List HpackEntry)))

(schema Http2Stream
  (:f streamId Int64)
  (:f state String)
  (:f windowSize Int64))

fn makeHttp2Frame frameType: Int64 flags: Int64 streamId: Int64 payload: String -> Http2Frame
  (Http2Frame :frameType frameType :flags flags :streamId streamId :length (stringLength payload) :payload payload)

fn makeDataFrame streamId: Int64 payload: String endStream: Bool -> Http2Frame
  (let [(f (if endStream (FLAG_END_STREAM) (FLAG_NONE)))]
    (Http2Frame :frameType (FRAME_DATA) :flags f :streamId streamId :length (stringLength payload) :payload payload))

fn makeHeadersFrame streamId: Int64 payload: String endHeaders: Bool endStream: Bool -> Http2Frame
  (let [(f1 (if endHeaders (FLAG_END_HEADERS) 0))
        (f2 (if endStream (FLAG_END_STREAM) 0))
        (f (+ f1 f2))]
    (Http2Frame :frameType (FRAME_HEADERS) :flags f :streamId streamId :length (stringLength payload) :payload payload))

fn makeSettingsFrame streamId: Int64 isAck: Bool payload: String -> Http2Frame
  (let [(f (if isAck (FLAG_ACK) (FLAG_NONE)))]
    (Http2Frame :frameType (FRAME_SETTINGS) :flags f :streamId streamId :length (stringLength payload) :payload payload))

fn makePingFrame payload: String isAck: Bool -> Http2Frame
  (let [(f (if isAck (FLAG_ACK) (FLAG_NONE)))]
    (Http2Frame :frameType (FRAME_PING) :flags f :streamId 0 :length (stringLength payload) :payload payload))

fn makeRstStreamFrame streamId: Int64 errorCode: Int64 -> Http2Frame
  (Http2Frame :frameType (FRAME_RST_STREAM) :flags 0 :streamId streamId :length 4 :payload (stringFromInt64 errorCode))

fn makeGoawayFrame lastStreamId: Int64 errorCode: Int64 debugMsg: String -> Http2Frame
  (let [(payload (str (stringFromInt64 lastStreamId) ":" (stringFromInt64 errorCode) ":" debugMsg))]
    (Http2Frame :frameType (FRAME_GOAWAY) :flags 0 :streamId 0 :length (stringLength payload) :payload payload))

fn makeWindowUpdateFrame streamId: Int64 windowSizeIncrement: Int64 -> Http2Frame
  (Http2Frame :frameType (FRAME_WINDOW_UPDATE) :flags 0 :streamId streamId :length 4 :payload (stringFromInt64 windowSizeIncrement))

fn hexNibble n: Int64 -> String
  (let [(v (mod n 16))]
    (cond
      ((= v 0) "0") ((= v 1) "1") ((= v 2) "2") ((= v 3) "3")
      ((= v 4) "4") ((= v 5) "5") ((= v 6) "6") ((= v 7) "7")
      ((= v 8) "8") ((= v 9) "9") ((= v 10) "a") ((= v 11) "b")
      ((= v 12) "c") ((= v 13) "d") ((= v 14) "e") (else "f")))

fn intToHexLoop v: Int64 d: Int64 acc: String -> String
  (if (<= d 0)
    acc
    (intToHexLoop (/ v 16) (- d 1) (str (hexNibble v) acc)))

fn intToHexFixed val: Int64 digits: Int64 -> String
  (intToHexLoop val digits "")

fn hexCharToInt c: String -> Int64
  (cond
    ((= c "0") 0) ((= c "1") 1) ((= c "2") 2) ((= c "3") 3)
    ((= c "4") 4) ((= c "5") 5) ((= c "6") 6) ((= c "7") 7)
    ((= c "8") 8) ((= c "9") 9)
    ((or (= c "a") (= c "A")) 10)
    ((or (= c "b") (= c "B")) 11)
    ((or (= c "c") (= c "C")) 12)
    ((or (= c "d") (= c "D")) 13)
    ((or (= c "e") (= c "E")) 14)
    ((or (= c "f") (= c "F")) 15)
    (else 0))

fn hexToInt s: String -> Int64
  (let [(chars (stringChars s))]
    (fold (fn [(acc Int64) (c String)] -> Int64
      (+ (* acc 16) (hexCharToInt c))) 0 chars))

fn encodeBinaryFrame frame: Http2Frame -> String
  (let [(lenHex (intToHexFixed frame.length 6))
        (typeHex (intToHexFixed frame.frameType 2))
        (flagsHex (intToHexFixed frame.flags 2))
        (streamHex (intToHexFixed frame.streamId 8))
        (headerHex (str lenHex typeHex flagsHex streamHex))]
    (str "BIN_H2:" headerHex ":" frame.payload))

fn decodeBinaryFrame raw: String -> (Result Http2Frame String)
  (if (or (stringEmpty? raw) (not (stringStartsWith? raw "BIN_H2:")))
    (err "ERR_H2_INVALID_BINARY_PREFIX")
    (let [(sub (optionOr (stringSlice raw 7 (stringLength raw)) ""))
          (colonIdx (stringIndexOf sub ":"))]
      (mt colonIdx
        ((none) (err "ERR_H2_TRUNCATED_BINARY_FRAME"))
        ((some idx)
          (if (!= idx 18)
            (err "ERR_H2_INVALID_HEADER_LENGTH")
            (let [(headerHex (optionOr (stringSlice sub 0 18) ""))
                  (payload (optionOr (stringSlice sub 19 (stringLength sub)) ""))
                  (lenHex (optionOr (stringSlice headerHex 0 6) ""))
                  (typeHex (optionOr (stringSlice headerHex 6 8) ""))
                  (flagsHex (optionOr (stringSlice headerHex 8 10) ""))
                  (streamHex (optionOr (stringSlice headerHex 10 18) ""))
                  (flen (hexToInt lenHex))
                  (ftype (hexToInt typeHex))
                  (fflags (hexToInt flagsHex))
                  (fstream (hexToInt streamHex))]
              (if (!= (stringLength payload) flen)
                (err "ERR_H2_FRAME_LENGTH_MISMATCH")
                (ok (Http2Frame :frameType ftype :flags fflags :streamId fstream :length flen :payload payload)))))))))

fn encodeHttp2Frame frame: Http2Frame -> String
  (str "H2F:" (stringFromInt64 frame.length) ":" (stringFromInt64 frame.frameType) ":" (stringFromInt64 frame.flags) ":" (stringFromInt64 frame.streamId) ":" frame.payload)

fn findNthColon s: String pos: Int64 remaining: Int64 -> (Option Int64)
  (if (<= remaining 0)
    (some pos)
    (let [(sub (optionOr (stringSlice s pos (stringLength s)) ""))
          (idx (stringIndexOf sub ":"))]
      (mt idx
        ((some off) (findNthColon s (+ (+ pos off) 1) (- remaining 1)))
        ((none) (none)))))

fn decodeHttp2Frame raw: String -> (Result Http2Frame String)
  (if (stringStartsWith? raw "BIN_H2:")
    (decodeBinaryFrame raw)
    (if (or (stringEmpty? raw) (not (stringStartsWith? raw "H2F:")))
      (err "ERR_H2_TRUNCATED_FRAME")
      (let [(fifthColonOpt (findNthColon raw 0 5))]
        (mt fifthColonOpt
          ((none) (err "ERR_H2_TRUNCATED_FRAME"))
          ((some headerEnd)
            (let [(headerPart (optionOr (stringSlice raw 0 (- headerEnd 1)) ""))
                  (payload (optionOr (stringSlice raw headerEnd (stringLength raw)) ""))
                  (tokens (stringSplit headerPart ":"))]
              (if (< (listLength tokens) 5)
                (err "ERR_H2_INVALID_HEADER")
                (let [(lenStr (optionOr (listHead (optionOr (listTail tokens) (list))) ""))
                      (typeStr (optionOr (listHead (optionOr (listTail (optionOr (listTail tokens) (list))) (list))) ""))
                      (flagsStr (optionOr (listHead (optionOr (listTail (optionOr (listTail (optionOr (listTail tokens) (list))) (list))) (list))) ""))
                      (streamStr (optionOr (listHead (optionOr (listTail (optionOr (listTail (optionOr (listTail (optionOr (listTail tokens) (list))) (list))) (list))) (list))) ""))
                      (len (optionOr (stringToInt64 lenStr) -1))
                      (fType (optionOr (stringToInt64 typeStr) -1))
                      (flags (optionOr (stringToInt64 flagsStr) -1))
                      (streamId (optionOr (stringToInt64 streamStr) -1))]
                  (if (or (or (< len 0) (< fType 0)) (or (< flags 0) (< streamId 0)))
                    (err "ERR_H2_INVALID_HEADER_FIELDS")
                    (if (!= (stringLength payload) len)
                      (err "ERR_H2_FRAME_LENGTH_MISMATCH")
                      (ok (Http2Frame :frameType fType :flags flags :streamId streamId :length len :payload payload))))))))))))

fn makeHpackTable maxSize: Int64 -> HpackTable
  (HpackTable :maxSize maxSize :currentSize 0 :entries (list))

fn calcEntrySize name: String value: String -> Int64
  (+ (+ (stringLength name) (stringLength value)) 32)

fn hpackTableEvict entries: (List HpackEntry) curSize: Int64 maxSize: Int64 -> (Pair (List HpackEntry) Int64)
  (if (or (listEmpty? entries) (<= curSize maxSize))
    (pair entries curSize)
    (let [(rev (listReverse entries))]
      (mt (listHead rev)
        ((none) (pair (list) 0))
        ((some oldest)
          (let [(reducedSize (- curSize oldest.size))
                (newRev (optionOr (listTail rev) (list)))
                (newEntries (listReverse newRev))]
            (hpackTableEvict newEntries reducedSize maxSize))))))

fn hpackTableAdd tbl: HpackTable name: String value: String -> HpackTable
  (let [(eSize (calcEntrySize name value))
        (entry (HpackEntry :name name :value value :size eSize))
        (newEntries (cons entry tbl.entries))
        (newSize (+ tbl.currentSize eSize))
        (evicted (hpackTableEvict newEntries newSize tbl.maxSize))]
    (with tbl :currentSize (pairSecond evicted) :entries (pairFirst evicted)))

fn formatHpackLines entries: (List (Pair String String)) -> String
  (if (listEmpty? entries)
    ""
    (let [(p (optionOr (listHead entries) (pair "" "")))
          (line (str (pairFirst p) "=" (pairSecond p) "\n"))
          (rest (formatHpackLines (optionOr (listTail entries) (list))))]
      (str line rest)))

fn encodeHpack tbl: HpackTable headers: http/HttpHeaders -> (Pair HpackTable String)
  (let [(pairs headers.entries)
        (encodedPayload (str "HPACK:" (stringFromInt64 (listLength pairs)) "\n" (formatHpackLines pairs)))
        (updatedTbl (fold (fn [(acc HpackTable) (p (pair String String))] -> HpackTable
          (hpackTableAdd acc (pairFirst p) (pairSecond p))) tbl pairs))]
    (pair updatedTbl encodedPayload))

fn parseHpackLine line: String -> (Option (Pair String String))
  (let [(eqPos (stringIndexOf line "="))]
    (mt eqPos
      ((some idx)
        (let [(k (optionOr (stringSlice line 0 idx) ""))
              (v (optionOr (stringSlice line (+ idx 1) (stringLength line)) ""))]
          (some (pair k v))))
      ((none) (none))))

fn parseHpackLinesLoop lines: (List String) acc: (List (Pair String String)) -> (List (Pair String String))
  (if (listEmpty? lines)
    (listReverse acc)
    (let [(line (stringTrim (optionOr (listHead lines) "")))]
      (if (stringEmpty? line)
        (parseHpackLinesLoop (optionOr (listTail lines) (list)) acc)
        (let [(pOpt (parseHpackLine line))]
          (mt pOpt
            ((some p) (parseHpackLinesLoop (optionOr (listTail lines) (list)) (cons p acc)))
            ((none) (parseHpackLinesLoop (optionOr (listTail lines) (list)) acc)))))))

fn decodeHpack tbl: HpackTable wireBlock: String -> (Result (Pair HpackTable http/HttpHeaders) String)
  (if (not (stringStartsWith? wireBlock "HPACK:"))
    (err "ERR_HPACK_INVALID_HEADER_BLOCK")
    (let [(newlinePos (stringIndexOf wireBlock "\n"))]
      (mt newlinePos
        ((none) (err "ERR_HPACK_MALFORMED_FORMAT"))
        ((some idx)
          (let [(bodyPart (optionOr (stringSlice wireBlock (+ idx 1) (stringLength wireBlock)) ""))
                (lines (stringSplit bodyPart "\n"))
                (entries (parseHpackLinesLoop lines (list)))
                (updatedTbl (fold (fn [(acc HpackTable) (p (pair String String))] -> HpackTable
                  (hpackTableAdd acc (pairFirst p) (pairSecond p))) tbl entries))]
            (ok (pair updatedTbl (http/makeHeaders entries))))))))
