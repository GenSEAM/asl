(module asl-http/tests/http2Test :x [runTests] :i [(asl-http/http2 :a h2) (asl-http/http11 :a http)])

fn testFrameConstants -> Bool
  (do
    (assert (= (h2/FRAME_DATA) 0) "FRAME_DATA must be 0")
    (assert (= (h2/FRAME_HEADERS) 1) "FRAME_HEADERS must be 1")
    (assert (= (h2/FRAME_PRIORITY) 2) "FRAME_PRIORITY must be 2")
    (assert (= (h2/FRAME_RST_STREAM) 3) "FRAME_RST_STREAM must be 3")
    (assert (= (h2/FRAME_SETTINGS) 4) "FRAME_SETTINGS must be 4")
    (assert (= (h2/FRAME_PUSH_PROMISE) 5) "FRAME_PUSH_PROMISE must be 5")
    (assert (= (h2/FRAME_PING) 6) "FRAME_PING must be 6")
    (assert (= (h2/FRAME_GOAWAY) 7) "FRAME_GOAWAY must be 7")
    (assert (= (h2/FRAME_WINDOW_UPDATE) 8) "FRAME_WINDOW_UPDATE must be 8")
    (assert (= (h2/FRAME_CONTINUATION) 9) "FRAME_CONTINUATION must be 9")
    (assert (= (h2/FLAG_NONE) 0) "FLAG_NONE must be 0")
    (assert (= (h2/FLAG_END_STREAM) 1) "FLAG_END_STREAM must be 1")
    (assert (= (h2/FLAG_END_HEADERS) 4) "FLAG_END_HEADERS must be 4")
    (refute (= (h2/FRAME_DATA) 1) "FRAME_DATA must refute 1")
    (refute (= (h2/FRAME_HEADERS) 0) "FRAME_HEADERS must refute 0")
    true)

fn testBinaryFrameCodec -> Bool
  (let [(dFrame (h2/makeDataFrame 1 "Hello HTTP/2 World" true))
        (binWire (h2/encodeBinaryFrame dFrame))]
    (do
      (assert (stringStartsWith? binWire "BIN_H2:") "Binary frame wire starts with BIN_H2:")
      (let [(decRes (h2/decodeBinaryFrame binWire))]
        (do
          (assert (ok? decRes) "Binary frame decoding must succeed")
          (mt decRes
            ((ok f)
              (do
                (assert (= f.frameType (h2/FRAME_DATA)) "Frame type must be FRAME_DATA")
                (assert (= f.flags (h2/FLAG_END_STREAM)) "Flags must carry FLAG_END_STREAM")
                (assert (= f.streamId 1) "Stream ID must be 1")
                (assert (= f.length 18) "Frame length must match payload size 18")
                (assert (= f.payload "Hello HTTP/2 World") "Payload content preserved")
                (refute (= f.streamId 2) "Stream ID 1 must refute 2")
                (refute (= f.length 99) "Payload length 18 must refute 99")
                true))
            ((err e)
              (do
                (assert false (str "Decoding failed: " e))
                false)))))))

fn testTypedFrameConstructors -> Bool
  (let [(hFrame (h2/makeHeadersFrame 3 "HEADER_BLOCK" true true))
        (sFrame (h2/makeSettingsFrame 0 false ""))
        (pFrame (h2/makePingFrame "12345678" true))
        (rFrame (h2/makeRstStreamFrame 5 (h2/ERR_CANCEL)))
        (gFrame (h2/makeGoawayFrame 10 (h2/ERR_NO_ERROR) "graceful shutdown"))
        (wFrame (h2/makeWindowUpdateFrame 1 65535))]
    (do
      (assert (= hFrame.frameType (h2/FRAME_HEADERS)) "Headers frame type must be 1")
      (assert (= hFrame.flags 5) "Headers frame flags must be END_HEADERS + END_STREAM = 5")
      (assert (= hFrame.streamId 3) "Headers streamId must be 3")
      (assert (= sFrame.frameType (h2/FRAME_SETTINGS)) "Settings frame type must be 4")
      (assert (= sFrame.flags 0) "Settings non-ACK flags must be 0")
      (assert (= pFrame.frameType (h2/FRAME_PING)) "Ping frame type must be 6")
      (assert (= pFrame.flags (h2/FLAG_ACK)) "Ping ACK flags must be 1")
      (assert (= rFrame.frameType (h2/FRAME_RST_STREAM)) "RST_STREAM frame type must be 3")
      (assert (= rFrame.payload (stringFromInt64 (h2/ERR_CANCEL))) "RST_STREAM carries cancel code")
      (assert (= gFrame.frameType (h2/FRAME_GOAWAY)) "GOAWAY frame type must be 7")
      (assert (= wFrame.frameType (h2/FRAME_WINDOW_UPDATE)) "WINDOW_UPDATE frame type must be 8")
      (refute (= hFrame.frameType (h2/FRAME_DATA)) "Headers frame must refute FRAME_DATA")
      (refute (= pFrame.flags 0) "Ping ACK must refute 0 flags")
      true))

fn testBinaryFrameErrors -> Bool
  (do
    (let [(res1 (h2/decodeBinaryFrame "INVALID_PREFIX:000000000000000000:"))]
      (do
        (assert (err? res1) "Missing BIN_H2 prefix must fail")
        (refute (ok? res1) "Missing prefix must refute ok")
        true))
    (let [(res2 (h2/decodeBinaryFrame "BIN_H2:SHORT:"))]
      (do
        (assert (err? res2) "Malformed header length must fail")
        true))
    (let [(res3 (h2/decodeBinaryFrame "BIN_H2:00000a000000000001:short"))]
      (do
        (assert (err? res3) "Length mismatch (expected 10, got 5) must fail")
        true)))

fn testBackwardCompatibleTextFrames -> Bool
  (let [(frame (h2/makeHttp2Frame 0 1 7 "Legacy text frame payload"))
        (encoded (h2/encodeHttp2Frame frame))
        (decodedRes (h2/decodeHttp2Frame encoded))]
    (do
      (assert (stringStartsWith? encoded "H2F:") "Text frame starts with H2F:")
      (assert (ok? decodedRes) "Decoding text frame succeeds")
      (mt decodedRes
        ((ok dec)
          (do
            (assert (= dec.streamId 7) "Decoded text frame streamId is 7")
            (assert (= dec.payload "Legacy text frame payload") "Decoded text payload matches")
            (refute (= dec.streamId 8) "StreamId 7 must refute 8")
            true))
        ((err _)
          (do
            (assert false "Decoding legacy text frame failed")
            false)))))

fn testHpackTableEviction -> Bool
  (let [(tbl0 (h2/makeHpackTable 100))
        (tbl1 (h2/hpackTableAdd tbl0 "k1" "v1"))
        (tbl2 (h2/hpackTableAdd tbl1 "k2" "v2"))
        (tbl3 (h2/hpackTableAdd tbl2 "long-header-key" "long-header-value-exceeding-small-limit"))]
    (do
      (assert (> tbl1.currentSize 0) "Hpack table size increases after add")
      (assert (<= tbl3.currentSize tbl3.maxSize) "Table current size stays bounded by maxSize")
      (assert (< (listLength tbl3.entries) 3) "Oldest entries must be evicted when limit exceeded")
      (refute (> tbl3.currentSize 100) "Table size must refute exceeding maxSize")
      true))

fn testHpackEncodeDecodeRoundtrip -> Bool
  (let [(tbl0 (h2/makeHpackTable 4096))
        (hdrs (http/makeHeaders (list (pair ":method" "GET") (pair ":path" "/api/v2/items") (pair "authorization" "Bearer token123"))))
        (encRes (h2/encodeHpack tbl0 hdrs))
        (tbl1 (pairFirst encRes))
        (wireBlock (pairSecond encRes))]
    (do
      (assert (stringStartsWith? wireBlock "HPACK:3\n") "Encoded wire block begins with HPACK:3 count")
      (assert (> tbl1.currentSize 0) "Table dynamic size updated after encoding")
      (let [(decRes (h2/decodeHpack (h2/makeHpackTable 4096) wireBlock))]
        (do
          (assert (ok? decRes) "Decoding HPACK block succeeds")
          (mt decRes
            ((ok pairRes)
              (let [(decHdrs (pairSecond pairRes))]
                (do
                  (assert (= (http/getHeaderFromHeaders decHdrs ":method") (some "GET")) "Method header matches GET")
                  (assert (= (http/getHeaderFromHeaders decHdrs ":path") (some "/api/v2/items")) "Path header matches /api/v2/items")
                  (assert (= (http/getHeaderFromHeaders decHdrs "authorization") (some "Bearer token123")) "Authorization header matches")
                  (refute (= (http/getHeaderFromHeaders decHdrs ":method") (some "POST")) ":method GET must refute POST")
                  true)))
            ((err e)
              (do
                (assert false (str "HPACK decode failed: " e))
                false)))))))

fn runTests -> Bool
  (do
    (assert (testFrameConstants) "testFrameConstants passed")
    (assert (testBinaryFrameCodec) "testBinaryFrameCodec passed")
    (assert (testTypedFrameConstructors) "testTypedFrameConstructors passed")
    (assert (testBinaryFrameErrors) "testBinaryFrameErrors passed")
    (assert (testBackwardCompatibleTextFrames) "testBackwardCompatibleTextFrames passed")
    (assert (testHpackTableEviction) "testHpackTableEviction passed")
    (assert (testHpackEncodeDecodeRoundtrip) "testHpackEncodeDecodeRoundtrip passed")
    true)
