(module asl-web/ssr :x [SsrStreamState makeSsrStreamState renderVNodeToHtmlStream serializeAsnState escapeScriptTag renderSsrDocument formatChunkedStream handleStreamBackpressure renderDocumentHtml serializeHydrationState parseHydrationState] :i [(vdom :a v) (html :a h)])

(schema SsrStreamState (:f status String) (:f bufferedChunks (List String)) (:f bytesBuffered Int64) (:f maxBufferBytes Int64) (:f chunksEmitted Int64))

fn makeSsrStreamState maxBufferBytes: Int64 -> SsrStreamState
  (SsrStreamState :status "streaming" :bufferedChunks (list) :bytesBuffered 0 :maxBufferBytes (if (<= maxBufferBytes 0) 65536 maxBufferBytes) :chunksEmitted 0)

fn escapeScriptTag payload: String -> String
  (stringReplace (stringReplace payload "</script>" "<\\/script>") "</SCRIPT>" "<\\/SCRIPT>")

fn serializeAsnState state: Any -> String
  (escapeScriptTag (str state))

fn hexDigitToChar d: Int64 -> String
  (if (= d 0) "0" (if (= d 1) "1" (if (= d 2) "2" (if (= d 3) "3" (if (= d 4) "4" (if (= d 5) "5" (if (= d 6) "6" (if (= d 7) "7" (if (= d 8) "8" (if (= d 9) "9" (if (= d 10) "a" (if (= d 11) "b" (if (= d 12) "c" (if (= d 13) "d" (if (= d 14) "e" "f")))))))))))))))

fn intToHexLoop n: Int64 acc: String -> String
  (if (<= n 0) (if (stringEmpty? acc) "0" acc) (let [(rem (mod n 16)) (quot (/ n 16)) (ch (hexDigitToChar rem))] (intToHexLoop quot (str ch acc))))

fn intToHex n: Int64 -> String
  (if (<= n 0) "0" (intToHexLoop n ""))

fn formatChunkedStream chunks: (List String) -> String
  (let [(encodedChunks (map (fn [(c String)] -> String (let [(len (stringLength c)) (hexLen (intToHex len))] (str hexLen "\r\n" c "\r\n"))) chunks)) (terminal "0\r\n\r\n")] (str (stringJoin encodedChunks "") terminal))

fn handleStreamBackpressure state: SsrStreamState socketEvent: String chunk: String -> SsrStreamState
  (if (or (= socketEvent "EPIPE") (= socketEvent "ECONNRESET")) (with state :status "cancelled" :bufferedChunks (list) :bytesBuffered 0) (if (or (= socketEvent "EAGAIN") (= socketEvent "EWOULDBLOCK")) (let [(newBuffered (listAppend state.bufferedChunks (list chunk))) (newBytes (+ state.bytesBuffered (stringLength chunk)))] (with state :status "paused" :bufferedChunks newBuffered :bytesBuffered newBytes)) (if (= socketEvent "DRAIN") (let [(drainCount (+ state.chunksEmitted (listLength state.bufferedChunks)))] (with state :status "streaming" :bufferedChunks (list) :bytesBuffered 0 :chunksEmitted drainCount)) (with state :chunksEmitted (+ state.chunksEmitted 1)))))

fn renderVNodeToHtmlStream root: v/VNode -> (List String)
  (mt root ((v/textNode content) (list (h/escapeHtml content))) ((v/elementNode tag attrs children) (if (or (= tag "raw") (= tag "!raw")) (list (optionOr (mapGet attrs "html") "")) (let [(attrStr (h/attrsToHtml attrs)) (openTag (str "<" tag attrStr ">")) (closeTag (if (h/isVoidTag? tag) "" (str "</" tag ">")))] (if (= (listLength children) 0) (list (if (h/isVoidTag? tag) openTag (str openTag closeTag))) (let [(childChunks (fold (fn [(acc (List String)) (ch v/VNode)] -> (List String) (listAppend acc (renderVNodeToHtmlStream ch))) (list) children))] (listAppend (list openTag) (listAppend childChunks (list closeTag)))))))))

fn renderSsrDocument title: String root: v/VNode state: Any -> (List String)
  (let [(headChunk (str "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>" (h/escapeHtml title) "</title></head><body><div id=\"app\">")) (bodyChunks (renderVNodeToHtmlStream root)) (stateStr (serializeAsnState state)) (tailChunk (str "</div><script type=\"application/asn\" id=\"asl-state\">" stateStr "</script></body></html>"))] (listAppend (list headChunk) (listAppend bodyChunks (list tailChunk))))

fn serializeHydrationState state: String -> String
  (str "<script type=\"text/asn\" id=\"__ASL_HYDRATION__\">" (escapeScriptTag state) "</script>")

fn parseHydrationState html: String -> (Option String)
  (let [(prefix "<script type=\"text/asn\" id=\"__ASL_HYDRATION__\">")
        (suffix "</script>")
        (startIdx (stringIndexOf html prefix))]
    (mt startIdx
      ((none) (none))
      ((some s)
        (let [(after (optionOr (stringSlice html (+ s (stringLength prefix)) (stringLength html)) ""))
              (endIdx (stringIndexOf after suffix))]
          (mt endIdx
            ((none) (none))
            ((some e) (some (optionOr (stringSlice after 0 e) ""))))))))

fn renderDocumentHtml title: String bodyHtml: String stateAsn: String -> String
  (str "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\">\n  <title>"
       title
       "</title>\n</head>\n<body>\n  <div id=\"app\">\n"
       bodyHtml
       "\n  </div>\n  "
       (serializeHydrationState stateAsn)
       "\n</body>\n</html>")

