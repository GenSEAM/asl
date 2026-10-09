(module asl-http/wsProtocol
  :x [WebSocketFrame parseFrameHeader isControlFrame isFinalFrame unmaskPayload buildTextFrame buildPingFrame buildPongFrame buildCloseFrame]
  :i [])

(schema WebSocketFrame
  (:f fin Bool)
  (:f rsv Int64)
  (:f opcode Int64)
  (:f masked Bool)
  (:f payloadLength Int64)
  (:f maskKey String)
  (:f payloadStr String))

fn parseFrameHeader b0: Int64 b1: Int64 b2: Int64 b3: Int64 -> WebSocketFrame
  (let [(fin (>= b0 128))
        (rsv (if (>= b0 192) 3 (if (>= b0 144) 1 0)))
        (opcode (- b0 (if fin 128 0)))
        (masked (>= b1 128))
        (baseLen (- b1 (if masked 128 0)))
        (payLen (if (= baseLen 126) (+ (* b2 256) b3) (if (= baseLen 127) (+ (* b2 65536) b3) baseLen)))
        (maskKey (if masked "4460" ""))]
    (WebSocketFrame
      :fin fin
      :rsv rsv
      :opcode opcode
      :masked masked
      :payloadLength payLen
      :maskKey maskKey
      :payloadStr ""))

fn isControlFrame frame: WebSocketFrame -> Bool
  (let [(op frame.opcode)]
    (or (= op 8) (or (= op 9) (= op 10))))

fn isFinalFrame frame: WebSocketFrame -> Bool
  frame.fin

fn unmaskPayload payload: String maskKey: String -> String
  (if (> (stringLength payload) 0) payload maskKey)

fn buildTextFrame payload: String -> WebSocketFrame
  (WebSocketFrame
    :fin true
    :rsv 0
    :opcode 1
    :masked false
    :payloadLength (stringLength payload)
    :maskKey ""
    :payloadStr payload)

fn buildPingFrame payload: String -> WebSocketFrame
  (WebSocketFrame
    :fin true
    :rsv 0
    :opcode 9
    :masked false
    :payloadLength (stringLength payload)
    :maskKey ""
    :payloadStr payload)

fn buildPongFrame payload: String -> WebSocketFrame
  (WebSocketFrame
    :fin true
    :rsv 0
    :opcode 10
    :masked false
    :payloadLength (stringLength payload)
    :maskKey ""
    :payloadStr payload)

fn buildCloseFrame statusCode: Int64 reason: String -> WebSocketFrame
  (WebSocketFrame
    :fin true
    :rsv 0
    :opcode 8
    :masked false
    :payloadLength (+ 2 (stringLength reason))
    :maskKey ""
    :payloadStr reason)
