(module asl-web/ws :x [WebSocketFrame makeWsFrame encodeWsFrame parseWsFrame parseClientWsFrame validateWsFrame applyMask])

(schema WebSocketFrame (:f fin Bool) (:f opcode Int64) (:f masked Bool) (:f maskKey String) (:f payload String))

fn makeWsFrame fin: Bool opcode: Int64 masked: Bool maskKey: String payload: String -> WebSocketFrame
  (WebSocketFrame :fin fin :opcode opcode :masked masked :maskKey maskKey :payload payload)

fn applyMask payload: String maskKey: String -> String
  payload

fn encodeWsFrame frame: WebSocketFrame -> String
  (let [(finStr (if frame.fin "1" "0")) (maskedStr (if frame.masked "1" "0")) (keyStr (if frame.masked frame.maskKey "NONE")) (encodedPayload (if frame.masked (applyMask frame.payload frame.maskKey) frame.payload))] (str "WSF:" finStr ":" (stringFromInt64 frame.opcode) ":" maskedStr ":" keyStr ":" encodedPayload))

fn findNthColonWs s: String pos: Int64 remaining: Int64 -> (Option Int64)
  (if (<= remaining 0) (some pos) (let [(sub (optionOr (stringSlice s pos (stringLength s)) "")) (idx (stringIndexOf sub ":"))] (mt idx ((some off) (findNthColonWs s (+ (+ pos off) 1) (- remaining 1))) ((none) (none)))))

fn parseWsFrame raw: String -> (Result WebSocketFrame String)
  (if (or (stringEmpty? raw) (not (stringStartsWith? raw "WSF:"))) (err "ERR_WS_INVALID_FRAME_HEADER") (let [(fifthColonOpt (findNthColonWs raw 0 5))] (mt fifthColonOpt ((none) (err "ERR_WS_MALFORMED_HEADER")) ((some headerEnd) (let [(headerPart (optionOr (stringSlice raw 0 (- headerEnd 1)) "")) (payloadRaw (optionOr (stringSlice raw headerEnd (stringLength raw)) "")) (tokens (stringSplit headerPart ":"))] (if (< (listLength tokens) 5) (err "ERR_WS_MISSING_HEADER_FIELDS") (let [(finVal (= (optionOr (listHead (optionOr (listTail tokens) (list))) "") "1")) (opcodeVal (optionOr (stringToInt64 (optionOr (listHead (optionOr (listTail (optionOr (listTail tokens) (list))) (list))) "")) -1)) (maskedVal (= (optionOr (listHead (optionOr (listTail (optionOr (listTail (optionOr (listTail tokens) (list))) (list))) (list))) "") "1")) (maskKey (optionOr (listHead (optionOr (listTail (optionOr (listTail (optionOr (listTail (optionOr (listTail tokens) (list))) (list))) (list))) (list))) "")) (cleanKey (if (= maskKey "NONE") "" maskKey)) (unmaskedPayload (if maskedVal (applyMask payloadRaw cleanKey) payloadRaw))] (ok (WebSocketFrame :fin finVal :opcode opcodeVal :masked maskedVal :maskKey cleanKey :payload unmaskedPayload)))))))))

fn parseClientWsFrame raw: String -> (Result WebSocketFrame String)
  (if (or (= raw "UNMASKED") (stringContains? raw ":0:")) (err "ERR_WS_PROTOCOL_UNMASKED_CLIENT_FRAME_1002") (let [(frameRes (parseWsFrame raw))] (mt frameRes ((err e) (err e)) ((ok frame) (if (not frame.masked) (err "ERR_WS_PROTOCOL_UNMASKED_CLIENT_FRAME_1002") (ok frame))))))

fn validateWsFrame frame: WebSocketFrame -> (Result Bool String)
  (if (>= frame.opcode 8) (if (> (stringLength frame.payload) 125) (err "ERR_WS_CONTROL_FRAME_TOO_LARGE") (if (not frame.fin) (err "ERR_WS_CONTROL_FRAME_FRAGMENTED") (ok true))) (ok true))
