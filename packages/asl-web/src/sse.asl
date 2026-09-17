(module asl-web/sse
  :d "Pure AgentScript Server-Sent Events Formatting, Streaming, and Parsing Pipeline"
  :x [SseEvent
      makeSseEvent
      formatSseEvent
      parseSseEvent])

(dfs SseEvent
  (:f id (Option String))
  (:f event (Option String))
  (:f data String)
  (:f retry (Option Int64)))

(df makeSseEvent [(id (Option String)) (event (Option String)) (data String) (retry (Option Int64))] -> SseEvent
  :d "Constructs SseEvent record"
  (SseEvent :id id :event event :data data :retry retry))

(df formatSseEvent [(ev SseEvent)] -> String
  :d "Serializes SseEvent record into RFC-compliant text/event-stream wire chunk"
  (let [(idPart (mt (.-id ev)
                  ((some i) (str "id: " i "\n"))
                  ((none) "")))
        (eventPart (mt (.-event ev)
                     ((some e) (str "event: " e "\n"))
                     ((none) "")))
        (dataPart (str "data: " (.-data ev) "\n"))
        (retryPart (mt (.-retry ev)
                     ((some r) (str "retry: " (string-from-int64 r) "\n"))
                     ((none) "")))]
    (str idPart eventPart dataPart retryPart "\n")))

(df extractFieldVal [(line String) (prefix String)] -> String
  :d "Extracts field value after designated prefix"
  (let [(pLen (string-length prefix))]
    (string-trim (option-or (string-slice line pLen (string-length line)) ""))))

(df parseSseLinesLoop [(lines (List String))
                       (id (Option String))
                       (event (Option String))
                       (data String)
                       (retry (Option Int64))] -> (Result SseEvent String)
  :d "Recursively parses text/event-stream lines into SseEvent"
  (if (list-empty? lines)
    (if (string-empty? data)
      (err "ERR_SSE_MISSING_DATA")
      (ok (SseEvent :id id :event event :data data :retry retry)))
    (let [(line (string-trim (option-or (list-head lines) "")))]
      (cond
        ((string-starts-with? line "data:")
         (let [(val (extractFieldVal line "data:"))
               (newData (if (string-empty? data) val (str data "\n" val)))]
           (parseSseLinesLoop (option-or (list-tail lines) (list)) id event newData retry)))
        ((string-starts-with? line "id:")
         (let [(val (extractFieldVal line "id:"))]
           (parseSseLinesLoop (option-or (list-tail lines) (list)) (some val) event data retry)))
        ((string-starts-with? line "event:")
         (let [(val (extractFieldVal line "event:"))]
           (parseSseLinesLoop (option-or (list-tail lines) (list)) id (some val) data retry)))
        ((string-starts-with? line "retry:")
         (let [(val (extractFieldVal line "retry:"))
               (rInt (string-to-int64 val))]
           (parseSseLinesLoop (option-or (list-tail lines) (list)) id event data rInt)))
        (:else
         (parseSseLinesLoop (option-or (list-tail lines) (list)) id event data retry))))))

(df parseSseEvent [(raw String)] -> (Result SseEvent String)
  :d "Parses text/event-stream wire chunk into SseEvent"
  (if (or (string-empty? raw) (not (string-contains? raw "data:")))
    (err "ERR_SSE_MISSING_DATA")
    (let [(normalized (string-replace raw "\r\n" "\n"))
          (lines (string-split normalized "\n"))]
      (parseSseLinesLoop lines (none) (none) "" (none)))))
