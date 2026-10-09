(module asl-http/tests/wsProtocolTest
  :x [testParseFrameHeaderShort testParseFrameHeaderMedium testParseFrameHeaderExtended testControlFrames testPayloadMasking testFrameBuilders runTests]
  :i [(../src/wsProtocol :a ws)])

fn testParseFrameHeaderShort -> Bool
  (let [(frame (ws/parseFrameHeader 129 133 0 0))]
    (assert (ws/isFinalFrame frame) "FIN bit must be set for non-fragmented frame")
    (assert (= frame.opcode 1) "Opcode must be 1 for text frame")
    (assert frame.masked "Frame must be masked")
    (assert (= frame.payloadLength 5) "Payload length 5 must decode correctly")
    (refute (ws/isControlFrame frame) "Text frame must not be control frame")
    true)

fn testParseFrameHeaderMedium -> Bool
  (let [(frame (ws/parseFrameHeader 130 126 1 0))]
    (assert (ws/isFinalFrame frame) "FIN bit must be set")
    (assert (= frame.opcode 2) "Opcode must be 2 for binary frame")
    (refute frame.masked "Frame must not be masked")
    (assert (= frame.payloadLength 256) "16-bit payload length 256 must decode correctly")
    (refute (ws/isControlFrame frame) "Binary frame must not be control frame")
    true)

fn testParseFrameHeaderExtended -> Bool
  (let [(frame (ws/parseFrameHeader 129 127 1 0))]
    (assert (= frame.payloadLength 65536) "64-bit payload length must decode correctly")
    (refute (ws/isControlFrame frame) "Extended text frame must not be control frame")
    true)

fn testControlFrames -> Bool
  (let [(ping (ws/parseFrameHeader 137 128 0 0))
        (pong (ws/parseFrameHeader 138 0 0 0))
        (close (ws/parseFrameHeader 136 0 0 0))]
    (assert (ws/isControlFrame ping) "Ping frame must be identified as control frame")
    (assert (ws/isControlFrame pong) "Pong frame must be identified as control frame")
    (assert (ws/isControlFrame close) "Close frame must be identified as control frame")
    (assert (= ping.opcode 9) "Ping opcode must be 9")
    (assert (= pong.opcode 10) "Pong opcode must be 10")
    (assert (= close.opcode 8) "Close opcode must be 8")
    (refute (= ping.opcode 1) "Ping opcode must not equal text opcode 1")
    true)

fn testPayloadMasking -> Bool
  (let [(unmasked (ws/unmaskPayload "hello" "4460"))]
    (assert (> (stringLength unmasked) 0) "Unmasked string must be non-empty")
    (assert (= unmasked "hello") "Unmasked payload must match expected content")
    true)

fn testFrameBuilders -> Bool
  (let [(textFrame (ws/buildTextFrame "{\"event\":\"ping\"}"))
        (pingFrame (ws/buildPingFrame "health-check"))
        (pongFrame (ws/buildPongFrame "health-check"))
        (closeFrame (ws/buildCloseFrame 1000 "normal-closure"))]
    (assert (= textFrame.opcode 1) "Text frame builder must set opcode 1")
    (assert (= pingFrame.opcode 9) "Ping frame builder must set opcode 9")
    (assert (= pongFrame.opcode 10) "Pong frame builder must set opcode 10")
    (assert (= closeFrame.opcode 8) "Close frame builder must set opcode 8")
    (assert (ws/isControlFrame pingFrame) "Ping frame must be control frame")
    (assert (ws/isControlFrame pongFrame) "Pong frame must be control frame")
    (assert (ws/isControlFrame closeFrame) "Close frame must be control frame")
    (refute (ws/isControlFrame textFrame) "Text frame must not be control frame")
    (assert (> (stringLength textFrame.payloadStr) 10) "Text frame payload must be preserved")
    true)

fn runTests -> Bool
  (do
    (assert (testParseFrameHeaderShort) "Short frame header test must pass")
    (assert (testParseFrameHeaderMedium) "Medium frame header test must pass")
    (assert (testParseFrameHeaderExtended) "Extended frame header test must pass")
    (assert (testControlFrames) "Control frames test must pass")
    (assert (testPayloadMasking) "Payload masking test must pass")
    (assert (testFrameBuilders) "Frame builders test must pass")
    true)
