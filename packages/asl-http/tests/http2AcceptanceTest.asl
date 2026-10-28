(module asl-http/tests/http2AcceptanceTest
  :x [runTests RunTests testBinaryFrameCodec testHpackTableEviction testFrameConstructors testDualPolarityRefutations]
  :i [(asl-http/http2 :a h2)])

fn testBinaryFrameCodec -> Bool
  (let [(frame (h2/makeDataFrame 1 "Hello HTTP/2 World" false))
        (encoded (h2/encodeBinaryFrame frame))
        (decodedRes (h2/decodeBinaryFrame encoded))]
    (assert (= frame.streamId 1) "frame streamId is 1")
    (refute (!= frame.streamId 1) "frame streamId refutes non-1")
    (assert (ok? decodedRes) "binary frame decodes ok")
    (refute (err? decodedRes) "binary frame decodes without error")
    (match decodedRes
      ((ok dec)
        (assert (= dec.frameType (h2/FRAME_DATA)) "decoded frameType is DATA")
        (refute (!= dec.frameType (h2/FRAME_DATA)) "decoded frameType refutes non-DATA")
        (assert (= dec.streamId 1) "decoded streamId matches 1")
        (refute (!= dec.streamId 1) "decoded streamId refutes mismatch")
        (assert (= dec.payload "Hello HTTP/2 World") "decoded payload matches original")
        (refute (!= dec.payload "Hello HTTP/2 World") "decoded payload refutes mismatch"))
      ((err _)
        (assert false "unexpected error in decodeBinaryFrame")
        (refute true "unexpected error in decodeBinaryFrame"))))
  true

fn testHpackTableEviction -> Bool
  (let [(tbl0 (h2/makeHpackTable 100))
        (tbl1 (h2/hpackTableAdd tbl0 "x-custom-1" "val1"))
        (tbl2 (h2/hpackTableAdd tbl1 "x-custom-2" "val2"))
        (tbl3 (h2/hpackTableAdd tbl2 "x-custom-3" "val3"))]
    (assert (<= tbl3.currentSize 100) "HPACK table respects max capacity via FIFO eviction")
    (refute (> tbl3.currentSize 100) "HPACK table refutes size exceeding maximum capacity")
    (assert (> (listLength tbl3.entries) 0) "HPACK table maintains active entries")
    (refute (listEmpty? tbl3.entries) "HPACK table refutes empty entries after additions"))
  true

fn testFrameConstructors -> Bool
  (let [(fData (h2/makeDataFrame 3 "data payload" true))
        (fHeaders (h2/makeHeadersFrame 5 "headers block" true true))
        (fSettings (h2/makeSettingsFrame 0 false ""))
        (fPing (h2/makePingFrame "12345678" false))
        (fRst (h2/makeRstStreamFrame 7 (h2/ERR_CANCEL)))
        (fGoaway (h2/makeGoawayFrame 9 (h2/ERR_NO_ERROR) "shutting down"))
        (fWin (h2/makeWindowUpdateFrame 0 65535))]
    (assert (= fData.frameType (h2/FRAME_DATA)) "makeDataFrame constructs FRAME_DATA")
    (assert (= fHeaders.frameType (h2/FRAME_HEADERS)) "makeHeadersFrame constructs FRAME_HEADERS")
    (assert (= fSettings.frameType (h2/FRAME_SETTINGS)) "makeSettingsFrame constructs FRAME_SETTINGS")
    (assert (= fPing.frameType (h2/FRAME_PING)) "makePingFrame constructs FRAME_PING")
    (assert (= fRst.frameType (h2/FRAME_RST_STREAM)) "makeRstStreamFrame constructs FRAME_RST_STREAM")
    (assert (= fGoaway.frameType (h2/FRAME_GOAWAY)) "makeGoawayFrame constructs FRAME_GOAWAY")
    (assert (= fWin.frameType (h2/FRAME_WINDOW_UPDATE)) "makeWindowUpdateFrame constructs FRAME_WINDOW_UPDATE")
    (refute (!= fRst.streamId 7) "fRst streamId refutes non-7")
    (refute (!= fPing.payload "12345678") "fPing payload refutes divergence"))
  true

fn testDualPolarityRefutations -> Bool
  (let [(shortData "0000010000000000")
        (shortDec (h2/decodeBinaryFrame shortData))]
    (assert (err? shortDec) "truncated binary frame header triggers error")
    (refute (ok? shortDec) "truncated binary frame header refutes ok"))
  true

fn runTests -> Bool
  (do
    (assert (testBinaryFrameCodec) "testBinaryFrameCodec passed")
    (assert (testHpackTableEviction) "testHpackTableEviction passed")
    (assert (testFrameConstructors) "testFrameConstructors passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
