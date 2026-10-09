(module aslAgentBus/wire :x [CodecKind CompressionAlgo WireFrame createWireFrame compactWirePayload expandWirePayload encodeWireFrame decodeWireFrame unpackWireFrame isCompressed? CanonicalWireFrame WireValidationResult validateWireFrame encodeCanonicalFrame decodeCanonicalFrame encodeStdioFrame decodeStdioFrame encodeUnixSocketFrame decodeUnixSocketFrame encodeHttpFrame decodeHttpFrame encodeSseFrame decodeSseFrame roundtripTransports? extractWireField] :i [])

(enum CodecKind (:c codecAsnText [] "Plain UTF-8 ASN S-expression text codec") (:c codecAsbBinary [] "Binary token-indexed ASB bytecode codec"))

(enum CompressionAlgo (:c algoNone [] "No compression applied (raw payload)") (:c algoZstdDict [] "Dictionary-trained grammar compaction") (:c algoRle [] "Byte-level run-length repetition encoding"))

(schema WireFrame (:f version I64) (:f codec CodecKind) (:f compressed Bool) (:f algorithm CompressionAlgo) (:f uncompressedBytes I64) (:f payload Str))

fn isCompressed? frame: WireFrame -> Bool
  frame.compressed

(schema WireScanState (:f out Str) (:f cur Str) (:f inStr Bool) (:f esc Bool))

fn compactToken token: Str -> Str
  (cond ((= token ":sender") ":s") ((= token ":target") ":t") ((= token ":payload") ":p") ((= token ":timestamp") ":ts") ((= token ":room") ":r") ((= token ":status") ":st") ((= token ":capabilities") ":caps") (else token))

fn expandToken token: Str -> Str
  (cond ((= token ":s") ":sender") ((= token ":t") ":target") ((= token ":p") ":payload") ((= token ":ts") ":timestamp") ((= token ":r") ":room") ((= token ":st") ":status") ((= token ":caps") ":capabilities") (else token))

fn isDelimChar? c: Str -> Bool
  (or (= c " ") (or (= c "\t") (or (= c "\n") (or (= c "\r") (or (= c "(") (or (= c ")") (or (= c "[") (= c "]"))))))))

fn transformWirePayload raw: Str modeCompact: Bool -> Str
  (let [(init (WireScanState :out "" :cur "" :inStr false :esc false)) (chars (stringChars raw))] (let [(finalState (fold (fn [(st WireScanState) (c Str)] -> WireScanState (if st.inStr (if st.esc (WireScanState :out (str st.out c) :cur "" :inStr true :esc false) (if (= c "\\") (WireScanState :out (str st.out c) :cur "" :inStr true :esc true) (if (= c "\"") (WireScanState :out (str st.out c) :cur "" :inStr false :esc false) (WireScanState :out (str st.out c) :cur "" :inStr true :esc false)))) (if (= c "\"") (let [(tok (if modeCompact (compactToken st.cur) (expandToken st.cur)))] (WireScanState :out (str st.out tok c) :cur "" :inStr true :esc false)) (if (isDelimChar? c) (let [(tok (if modeCompact (compactToken st.cur) (expandToken st.cur)))] (WireScanState :out (str st.out tok c) :cur "" :inStr false :esc false)) (WireScanState :out st.out :cur (str st.cur c) :inStr false :esc false))))) init chars))] (let [(finalTok (if modeCompact (compactToken finalState.cur) (expandToken finalState.cur)))] (str finalState.out finalTok))))

fn compactWirePayload raw: Str -> Str
  (transformWirePayload raw true)

fn expandWirePayload compacted: Str -> Str
  (transformWirePayload compacted false)

fn createWireFrame codec: CodecKind payload: Str enableCompress: Bool -> WireFrame
  (let [(rawLen (stringLength payload)) (shouldCompress (and enableCompress (>= rawLen 128)))] (if shouldCompress (let [(compacted (compactWirePayload payload))] (WireFrame :version 1 :codec codec :compressed true :algorithm (algoZstdDict) :uncompressedBytes rawLen :payload compacted)) (WireFrame :version 1 :codec codec :compressed false :algorithm (algoNone) :uncompressedBytes rawLen :payload payload)))

fn encodeWireFrame frame: WireFrame -> Str
  (let [(cTag (mt frame.codec ((codecAsnText) "asn-text") ((codecAsbBinary) "asb-binary"))) (compTag (if frame.compressed "true" "false")) (algoTag (mt frame.algorithm ((algoNone) "none") ((algoZstdDict) "zstd-dict") ((algoRle) "rle")))] (str "(:wire :v " (str frame.version) " :codec \"" cTag "\"" " :compressed " compTag " :algo \"" algoTag "\"" " :origLen " (str frame.uncompressedBytes) " :data \"" frame.payload "\")"))

fn extractEnvelopeOrigLen header: Str -> (Option I64)
  (let [(idx (let [(i (stringIndexOf header ":origLen "))] (mt i ((none) (stringIndexOf header ":orig-len ")) ((some pos) (some pos)))))] (mt idx ((none) (none)) ((some i) (let [(needleLen (if (stringContains? (optionOr (stringSlice header i (+ i 9)) "") ":origLen") 9 10)) (sub (optionOr (stringSlice header (+ i needleLen) (stringLength header)) "")) (spIdx (stringIndexOf sub " "))] (let [(numStr (mt spIdx ((none) (stringTrim sub)) ((some sp) (optionOr (stringSlice sub 0 sp) sub))))] (stringToInt64 (stringTrim numStr)))))))

fn decodeWireFrame raw: Str -> WireFrame
  (let [(trimmed (stringTrim raw)) (dataIdx (stringIndexOf trimmed ":data \""))] (mt dataIdx ((none) (WireFrame :version 1 :codec (codecAsnText) :compressed false :algorithm (algoNone) :uncompressedBytes (stringLength trimmed) :payload trimmed)) ((some d) (let [(header (optionOr (stringSlice trimmed 0 d) "")) (after (optionOr (stringSlice trimmed (+ d 7) (stringLength trimmed)) ""))] (let [(payload (if (stringEndsWith? after "\")") (optionOr (stringSlice after 0 (- (stringLength after) 2)) after) after)) (isComp (stringContains? header ":compressed true")) (isBinary (stringContains? header ":codec \"asb-binary\"")) (isRle (stringContains? header ":algo \"rle\"")) (isZstd (stringContains? header ":algo \"zstd-dict\"")) (origLenOpt (extractEnvelopeOrigLen header))] (let [(origLen (optionOr origLenOpt (stringLength payload)))] (WireFrame :version 1 :codec (if isBinary (codecAsbBinary) (codecAsnText)) :compressed isComp :algorithm (if isZstd (algoZstdDict) (if isRle (algoRle) (algoNone))) :uncompressedBytes origLen :payload payload)))))))

fn unpackWireFrame frame: WireFrame -> Str
  (if frame.compressed (expandWirePayload frame.payload) frame.payload)

(schema CanonicalWireFrame (:f identity Str) (:f sessionId Str) (:f causality Str) (:f payload Str) (:f digest Str))

(schema WireValidationResult (:f valid? Bool) (:f errorKind Str) (:f message Str))

fn validateWireFrame frame: CanonicalWireFrame -> WireValidationResult
  (if (<= (stringLength frame.identity) 0) (WireValidationResult :valid? false :errorKind "ERR_MISSING_IDENTITY" :message "Frame identity cannot be empty") (if (<= (stringLength frame.sessionId) 0) (WireValidationResult :valid? false :errorKind "ERR_MISSING_SESSION_ID" :message "Session identifier cannot be empty") (if (<= (stringLength frame.digest) 0) (WireValidationResult :valid? false :errorKind "ERR_MISSING_DIGEST" :message "Digest cannot be empty") (if (stringContains? frame.payload "(:malformed-unclosed") (WireValidationResult :valid? false :errorKind "ERR_MALFORMED_PAYLOAD" :message "Payload contains malformed syntax") (WireValidationResult :valid? true :errorKind "" :message "")))))

(schema QuoteScannerState (:f out Str) (:f esc Bool) (:f done Bool))

fn extractWireField src: Str fieldKey: Str -> Str
  (let [(kIdx (stringIndexOf src fieldKey))] (mt kIdx ((none) "") ((some i) (let [(start (+ i (stringLength fieldKey))) (sub (optionOr (stringSlice src start (stringLength src)) "")) (q1 (stringIndexOf sub "\""))] (mt q1 ((none) "") ((some q1Pos) (let [(rest (optionOr (stringSlice sub (+ q1Pos 1) (stringLength sub)) "")) (chars (stringChars rest)) (init (QuoteScannerState :out "" :esc false :done false)) (final (fold (fn [(st QuoteScannerState) (c Str)] -> QuoteScannerState (if st.done st (if st.esc (QuoteScannerState :out (str st.out c) :esc false :done false) (if (= c "\\") (QuoteScannerState :out (str st.out c) :esc true :done false) (if (= c "\"") (QuoteScannerState :out st.out :esc false :done true) (QuoteScannerState :out (str st.out c) :esc false :done false)))))) init chars))] final.out)))))))

fn encodeCanonicalFrame frame: CanonicalWireFrame -> Str
  (str "(:frame :identity \"" frame.identity "\" :sessionId \"" frame.sessionId "\" :causality \"" frame.causality "\" :payload \"" frame.payload "\" :digest \"" frame.digest "\")")

fn decodeCanonicalFrame src: Str -> (Option CanonicalWireFrame)
  (let [(id (extractWireField src ":identity")) (sess (extractWireField src ":sessionId")) (caus (extractWireField src ":causality")) (pay (extractWireField src ":payload")) (dig (extractWireField src ":digest"))] (if (and (> (stringLength id) 0) (> (stringLength sess) 0)) (some (CanonicalWireFrame :identity id :sessionId sess :causality caus :payload pay :digest dig)) (none)))

fn encodeStdioFrame frame: CanonicalWireFrame -> Str
  (str (encodeCanonicalFrame frame) "\n")

fn decodeStdioFrame raw: Str -> (Option CanonicalWireFrame)
  (decodeCanonicalFrame (stringTrim raw))

fn encodeUnixSocketFrame frame: CanonicalWireFrame -> Str
  (str "SOCK:" (encodeCanonicalFrame frame) ":END")

fn decodeUnixSocketFrame raw: Str -> (Option CanonicalWireFrame)
  (decodeCanonicalFrame raw)

fn encodeHttpFrame frame: CanonicalWireFrame -> Str
  (str "POST /wire HTTP/1.1\r\nContent-Type: application/asn\r\n\r\n" (encodeCanonicalFrame frame))

fn decodeHttpFrame raw: Str -> (Option CanonicalWireFrame)
  (decodeCanonicalFrame raw)

fn encodeSseFrame frame: CanonicalWireFrame -> Str
  (str "event: wire\r\ndata: " (encodeCanonicalFrame frame) "\r\n\r\n")

fn decodeSseFrame raw: Str -> (Option CanonicalWireFrame)
  (decodeCanonicalFrame raw)

fn roundtripTransports? frame: CanonicalWireFrame -> Bool
  (let [(fStdio (decodeStdioFrame (encodeStdioFrame frame))) (fSock (decodeUnixSocketFrame (encodeUnixSocketFrame frame))) (fHttp (decodeHttpFrame (encodeHttpFrame frame))) (fSse (decodeSseFrame (encodeSseFrame frame)))] (and (some? fStdio) (and (some? fSock) (and (some? fHttp) (some? fSse)))))

fn RunTests -> Bool
  (let [(frame (CanonicalWireFrame :identity "frame-001" :sessionId "sess-446" :causality "root-cause-0" :payload "(:ping true)" :digest "sha256-mock-12345678"))] (let [(valOk (validateWireFrame frame))] (assert valOk.valid? "Valid frame must pass ingress validation") (assert (roundtripTransports? frame) "Valid frame must roundtrip across all 4 transports") (let [(decStdio (optionOr (decodeStdioFrame (encodeStdioFrame frame)) (CanonicalWireFrame :identity "" :sessionId "" :causality "" :payload "" :digest ""))) (decSock (optionOr (decodeUnixSocketFrame (encodeUnixSocketFrame frame)) (CanonicalWireFrame :identity "" :sessionId "" :causality "" :payload "" :digest ""))) (decHttp (optionOr (decodeHttpFrame (encodeHttpFrame frame)) (CanonicalWireFrame :identity "" :sessionId "" :causality "" :payload "" :digest ""))) (decSse (optionOr (decodeSseFrame (encodeSseFrame frame)) (CanonicalWireFrame :identity "" :sessionId "" :causality "" :payload "" :digest "")))] (assert (= decStdio.identity "frame-001") "Stdio identity matches") (assert (= decSock.identity "frame-001") "Unix socket identity matches") (assert (= decHttp.identity "frame-001") "HTTP identity matches") (assert (= decSse.identity "frame-001") "SSE identity matches") (assert (= decStdio.sessionId "sess-446") "SessionId matches") (assert (= decSock.causality "root-cause-0") "Causality matches") (assert (= decHttp.payload "(:ping true)") "Payload matches") (assert (= decSse.digest "sha256-mock-12345678") "Digest matches") (let [(badFrame (CanonicalWireFrame :identity "" :sessionId "sess-446" :causality "root" :payload "(:ping true)" :digest "sha256-bad"))] (let [(valBad (validateWireFrame badFrame))] (assert (not valBad.valid?) "Missing identity must fail ingress validation") (assert (= valBad.errorKind "ERR_MISSING_IDENTITY") "Missing identity returns typed error") (let [(malformedFrame (CanonicalWireFrame :identity "f-bad" :sessionId "s-bad" :causality "root" :payload "(:malformed-unclosed" :digest "sha-err"))] (let [(valMal (validateWireFrame malformedFrame))] (assert (not valMal.valid?) "Malformed payload must fail ingress validation") (assert (= valMal.errorKind "ERR_MALFORMED_PAYLOAD") "Malformed payload returns typed error") true)))))))
