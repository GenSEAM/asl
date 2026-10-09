(module asl-web/sse :x [SseEvent makeSseEvent formatSseEvent parseSseEvent])

(schema SseEvent (:f id (Option String)) (:f event (Option String)) (:f data String) (:f retry (Option Int64)))

fn makeSseEvent id: (Option String) event: (Option String) data: String retry: (Option Int64) -> SseEvent
  (SseEvent :id id :event event :data data :retry retry)

fn formatSseEvent ev: SseEvent -> String
  (let [(idPart (mt ev.id ((some i) (str "id: " i "\n")) ((none) ""))) (eventPart (mt ev.event ((some e) (str "event: " e "\n")) ((none) ""))) (dataPart (str "data: " ev.data "\n")) (retryPart (mt ev.retry ((some r) (str "retry: " (stringFromInt64 r) "\n")) ((none) "")))] (str idPart eventPart dataPart retryPart "\n"))

fn extractFieldVal line: String prefix: String -> String
  (let [(pLen (stringLength prefix))] (stringTrim (optionOr (stringSlice line pLen (stringLength line)) "")))

fn parseSseLinesLoop lines: (List String) id: (Option String) event: (Option String) data: String retry: (Option Int64) -> (Result SseEvent String)
  (if (listEmpty? lines) (if (stringEmpty? data) (err "ERR_SSE_MISSING_DATA") (ok (SseEvent :id id :event event :data data :retry retry))) (let [(line (stringTrim (optionOr (listHead lines) "")))] (cond ((stringStartsWith? line "data:") (let [(val (extractFieldVal line "data:")) (newData (if (stringEmpty? data) val (str data "\n" val)))] (parseSseLinesLoop (optionOr (listTail lines) (list)) id event newData retry))) ((stringStartsWith? line "id:") (let [(val (extractFieldVal line "id:"))] (parseSseLinesLoop (optionOr (listTail lines) (list)) (some val) event data retry))) ((stringStartsWith? line "event:") (let [(val (extractFieldVal line "event:"))] (parseSseLinesLoop (optionOr (listTail lines) (list)) id (some val) data retry))) ((stringStartsWith? line "retry:") (let [(val (extractFieldVal line "retry:")) (rInt (stringToInt64 val))] (parseSseLinesLoop (optionOr (listTail lines) (list)) id event data rInt))) (else (parseSseLinesLoop (optionOr (listTail lines) (list)) id event data retry)))))

fn parseSseEvent raw: String -> (Result SseEvent String)
  (if (or (stringEmpty? raw) (not (stringContains? raw "data:"))) (err "ERR_SSE_MISSING_DATA") (let [(normalized (stringReplace raw "\r\n" "\n")) (lines (stringSplit normalized "\n"))] (parseSseLinesLoop lines (none) (none) "" (none))))
