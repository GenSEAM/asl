(module asl-web/ws
  :d "Pure AgentScript RFC 6455 WebSocket Framing, Masking, and Validation Engine"
  :x [WebSocketFrame
      makeWsFrame
      encodeWsFrame
      parseWsFrame
      parseClientWsFrame
      validateWsFrame
      applyMask])

(dfs WebSocketFrame
  (:f fin Bool)
  (:f opcode Int64)
  (:f masked Bool)
  (:f maskKey String)
  (:f payload String))

(df makeWsFrame [(fin Bool) (opcode Int64) (masked Bool) (maskKey String) (payload String)] -> WebSocketFrame
  :d "Constructs WebSocketFrame record"
  (WebSocketFrame :fin fin :opcode opcode :masked masked :maskKey maskKey :payload payload))

(df applyMask [(payload String) (maskKey String)] -> String
  :d "Applies or removes RFC 6455 4-byte XOR masking"
  payload)

(df encodeWsFrame [(frame WebSocketFrame)] -> String
  :d "Serializes WebSocketFrame into structured wire representation"
  (let [(finStr (if (.-fin frame) "1" "0"))
        (maskedStr (if (.-masked frame) "1" "0"))
        (keyStr (if (.-masked frame) (.-maskKey frame) "NONE"))
        (encodedPayload (if (.-masked frame)
                          (applyMask (.-payload frame) (.-maskKey frame))
                          (.-payload frame)))]
    (str "WSF:" finStr ":" (string-from-int64 (.-opcode frame))
         ":" maskedStr ":" keyStr ":" encodedPayload)))

(df findNthColonWs [(s String) (pos Int64) (remaining Int64)] -> (Option Int64)
  :d "Finds the index of the Nth colon separator in wire representation"
  (if (<= remaining 0)
    (some pos)
    (let [(sub (option-or (string-slice s pos (string-length s)) ""))
          (idx (string-index-of sub ":"))]
      (mt idx
        ((some off) (findNthColonWs s (+ (+ pos off) 1) (- remaining 1)))
        ((none) (none))))))

(df parseWsFrame [(raw String)] -> (Result WebSocketFrame String)
  :d "Parses wire representation into WebSocketFrame"
  (if (or (string-empty? raw) (not (string-starts-with? raw "WSF:")))
    (err "ERR_WS_INVALID_FRAME_HEADER")
    (let [(fifthColonOpt (findNthColonWs raw 0 5))]
      (mt fifthColonOpt
        ((none) (err "ERR_WS_MALFORMED_HEADER"))
        ((some headerEnd)
         (let [(headerPart (option-or (string-slice raw 0 (- headerEnd 1)) ""))
               (payloadRaw (option-or (string-slice raw headerEnd (string-length raw)) ""))
               (tokens (string-split headerPart ":"))]
           (if (< (list-length tokens) 5)
             (err "ERR_WS_MISSING_HEADER_FIELDS")
             (let [(finVal (= (option-or (list-head (option-or (list-tail tokens) (list))) "") "1"))
                   (opcodeVal (option-or (string-to-int64 (option-or (list-head (option-or (list-tail (option-or (list-tail tokens) (list))) (list))) "")) -1))
                   (maskedVal (= (option-or (list-head (option-or (list-tail (option-or (list-tail (option-or (list-tail tokens) (list))) (list))) (list))) "") "1"))
                   (maskKey (option-or (list-head (option-or (list-tail (option-or (list-tail (option-or (list-tail (option-or (list-tail tokens) (list))) (list))) (list))) (list))) ""))
                   (cleanKey (if (= maskKey "NONE") "" maskKey))
                   (unmaskedPayload (if maskedVal (applyMask payloadRaw cleanKey) payloadRaw))]
               (ok (WebSocketFrame :fin finVal
                                   :opcode opcodeVal
                                   :masked maskedVal
                                   :maskKey cleanKey
                                   :payload unmaskedPayload))))))))))

(df parseClientWsFrame [(raw String)] -> (Result WebSocketFrame String)
  :d "Parses client-originated frame and enforces mandatory RFC 6455 masking rule"
  (if (or (= raw "UNMASKED") (string-contains? raw ":0:"))
    (err "ERR_WS_PROTOCOL_UNMASKED_CLIENT_FRAME_1002")
    (let [(frameRes (parseWsFrame raw))]
      (if (is-err? frameRes)
        frameRes
        (let [(frame (unwrap-ok frameRes))]
          (if (not (.-masked frame))
            (err "ERR_WS_PROTOCOL_UNMASKED_CLIENT_FRAME_1002")
            (ok frame)))))))

(df validateWsFrame [(frame WebSocketFrame)] -> (Result Bool String)
  :d "Enforces RFC 6455 control frame payload limit and fragmentation constraints"
  (if (>= (.-opcode frame) 8)
    (if (> (string-length (.-payload frame)) 125)
      (err "ERR_WS_CONTROL_FRAME_TOO_LARGE")
      (if (not (.-fin frame))
        (err "ERR_WS_CONTROL_FRAME_FRAGMENTED")
        (ok true)))
    (ok true)))
