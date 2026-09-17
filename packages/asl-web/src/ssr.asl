(module asl-web/ssr
  :d "Pure AgentScript Streaming Server-Side Rendering and RFC 9112 Chunked HTML Pipeline"
  :x [SsrStreamState
      makeSsrStreamState
      renderVNodeToHtmlStream
      serializeAsnState
      escapeScriptTag
      renderSsrDocument
      formatChunkedStream
      handleStreamBackpressure]
  :i [(vdom :a v)
      (html :a h)])

(dfs SsrStreamState
  (:f status String)
  (:f bufferedChunks (List String))
  (:f bytesBuffered Int64)
  (:f maxBufferBytes Int64)
  (:f chunksEmitted Int64))

(df makeSsrStreamState [(maxBufferBytes Int64)] -> SsrStreamState
  :d "Constructs SsrStreamState with specified buffer ceiling"
  (SsrStreamState :status "streaming"
                  :bufferedChunks (list)
                  :bytesBuffered 0
                  :maxBufferBytes (if (<= maxBufferBytes 0) 65536 maxBufferBytes)
                  :chunksEmitted 0))

(df escapeScriptTag [(payload String)] -> String
  :d "Escapes closing script tag sequences to prevent HTML script tag breakout"
  (string-replace (string-replace payload "</script>" "<\\/script>") "</SCRIPT>" "<\\/SCRIPT>"))

(df serializeAsnState [(state Any)] -> String
  :d "Serializes arbitrary state into a compact script-safe ASN expression"
  (escapeScriptTag (str state)))

(df hexDigitToChar [(d Int64)] -> String
  :d "Converts decimal digit 0-15 to lowercase hex character"
  (if (= d 0) "0"
    (if (= d 1) "1"
      (if (= d 2) "2"
        (if (= d 3) "3"
          (if (= d 4) "4"
            (if (= d 5) "5"
              (if (= d 6) "6"
                (if (= d 7) "7"
                  (if (= d 8) "8"
                    (if (= d 9) "9"
                      (if (= d 10) "a"
                        (if (= d 11) "b"
                          (if (= d 12) "c"
                            (if (= d 13) "d"
                              (if (= d 14) "e"
                                "f"))))))))))))))))

(df intToHexLoop [(n Int64) (acc String)] -> String
  :d "Recursively builds hex string from Int64"
  (if (<= n 0)
    (if (string-empty? acc) "0" acc)
    (let [(rem (mod n 16))
          (quot (/ n 16))
          (ch (hexDigitToChar rem))]
      (intToHexLoop quot (str ch acc)))))

(df intToHex [(n Int64)] -> String
  :d "Converts non-negative Int64 to hex string"
  (if (<= n 0) "0" (intToHexLoop n "")))

(df formatChunkedStream [(chunks (List String))] -> String
  :d "Encodes a list of HTML string chunks into RFC 9112 chunked transfer framing"
  (let [(encodedChunks (map (fn [(c String)] -> String
                              (let [(len (string-length c))
                                    (hexLen (intToHex len))]
                                (str hexLen "\r\n" c "\r\n")))
                            chunks))
        (terminal "0\r\n\r\n")]
    (str (string-join encodedChunks "") terminal)))

(df handleStreamBackpressure [(state SsrStreamState) (socketEvent String) (chunk String)] -> SsrStreamState
  :d "Handles socket backpressure events: EAGAIN pauses, DRAIN resumes, EPIPE cancels"
  (if (or (= socketEvent "EPIPE") (= socketEvent "ECONNRESET"))
    (SsrStreamState :status "cancelled"
                    :bufferedChunks (list)
                    :bytesBuffered 0
                    :maxBufferBytes (.-maxBufferBytes state)
                    :chunksEmitted (.-chunksEmitted state))
    (if (or (= socketEvent "EAGAIN") (= socketEvent "EWOULDBLOCK"))
      (let [(newBuffered (list-append (.-bufferedChunks state) (list chunk)))
            (newBytes (+ (.-bytesBuffered state) (string-length chunk)))]
        (SsrStreamState :status "paused"
                        :bufferedChunks newBuffered
                        :bytesBuffered newBytes
                        :maxBufferBytes (.-maxBufferBytes state)
                        :chunksEmitted (.-chunksEmitted state)))
      (if (= socketEvent "DRAIN")
        (let [(drainCount (+ (.-chunksEmitted state) (list-length (.-bufferedChunks state))))]
          (SsrStreamState :status "streaming"
                          :bufferedChunks (list)
                          :bytesBuffered 0
                          :maxBufferBytes (.-maxBufferBytes state)
                          :chunksEmitted drainCount))
        (SsrStreamState :status (.-status state)
                        :bufferedChunks (.-bufferedChunks state)
                        :bytesBuffered (.-bytesBuffered state)
                        :maxBufferBytes (.-maxBufferBytes state)
                        :chunksEmitted (+ (.-chunksEmitted state) 1))))))

(df renderVNodeToHtmlStream [(root v/VNode)] -> (List String)
  :d "Renders a VNode tree into ordered streamable HTML chunks"
  (mt root
    ((v/textNode content)
     (list (h/escapeHtml content)))
    ((v/elementNode tag attrs children)
     (if (or (= tag "raw") (= tag "!raw"))
       (list (option-or (map-get attrs "html") ""))
       (let [(attrStr (h/attrsToHtml attrs))
             (openTag (str "<" tag attrStr ">"))
             (closeTag (if (h/isVoidTag? tag) "" (str "</" tag ">")))]
         (if (= (list-length children) 0)
           (list (if (h/isVoidTag? tag) openTag (str openTag closeTag)))
           (let [(childChunks (list-fold (fn [(acc (List String)) (ch v/VNode)] -> (List String)
                                           (list-concat acc (renderVNodeToHtmlStream ch)))
                                         (list)
                                         children))]
             (list-concat (list openTag) (list-append childChunks (list closeTag))))))))))

(df renderSsrDocument [(title String) (root v/VNode) (state Any)] -> (List String)
  :d "Renders a complete HTML5 document with embedded compact ASN application state"
  (let [(headChunk (str "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>"
                        (h/escapeHtml title)
                        "</title></head><body><div id=\"app\">"))
        (bodyChunks (renderVNodeToHtmlStream root))
        (stateStr (serializeAsnState state))
        (tailChunk (str "</div><script type=\"application/asn\" id=\"asl-state\">"
                        stateStr
                        "</script></body></html>"))]
    (list-concat (list headChunk) (list-append bodyChunks (list tailChunk)))))
