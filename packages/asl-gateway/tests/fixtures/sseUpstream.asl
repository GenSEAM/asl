(module aslGateway/tests/fixtures/sseUpstream
  :x [main]
  :i [])

; (:m :ref GW-SYNTHETIC-INFINITE-STREAM :do "stand-in for a stream-only upstream (Synthetic infinite mode): bin/asl run sseUpstream.asl PORTFILE SEENFILE PAUSEMS DEADLINESEC listens on a free port, writes it to PORTFILE, answers one request, records it in SEENFILE and exits; a request without stream true gets 400 as the real provider does, one with it gets SSE chunks with PAUSEMS silences between them; no connection before DEADLINESEC ends it with exit 2")

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn ! writeAll! fd: Int64 data: String -> Bool
  (if (stringEmpty? data) true
    (match (fdWrite fd data)
      ((err _) false)
      ((ok n) (if (<= n 0) false (writeAll! fd (optionOr (stringSlice data n (stringLength data)) ""))))))

fn headValue head: String name: String -> String
  (fold (fn [(acc String) (line String)] -> String
          (if (stringStartsWith? (stringLower line) (str (stringLower name) ":"))
            (stringTrim (optionOr (stringSlice line (+ (stringLength name) 1) (stringLength line)) ""))
            acc))
        ""
        (stringSplit head "\r\n"))

fn requestDone? raw: String -> Bool
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) false)
    ((some at)
      (let [(head (optionOr (stringSlice raw 0 at) ""))
            (want (optionOr (stringToInt64 (headValue head "Content-Length")) 0))]
        (>= (- (stringLength raw) (+ at 4)) want))))

fn ! readRequest! fd: Int64 deadline: Int64 acc: String -> String
  (if (or (requestDone? acc) (>= (nowMs!) deadline)) acc
    (match (fdPoll (list (pair fd 1)) 100)
      ((err _) acc)
      ((ok ready)
        (if (listEmpty? ready) (readRequest! fd deadline acc)
          (match (fdRead fd 65536)
            ((err _) acc)
            ((ok chunk) (if (stringEmpty? chunk) acc (readRequest! fd deadline (str acc chunk)))))))))

fn chunks -> (List String)
  (list "data: {\"id\":\"s1\",\"model\":\"syn-1017\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"reasoning_content\":\"think \"},\"finish_reason\":null}]}\n\n"
        ": keepalive\n\n"
        "data: {\"id\":\"s1\",\"model\":\"syn-1017\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning_content\":\"more\"},\"finish_reason\":null}]}\n\n"
        "data: {\"id\":\"s1\",\"model\":\"syn-1017\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"(:step \"},\"finish_reason\":null}]}\n\n"
        ": keepalive\n\n"
        "data: {\"id\":\"s1\",\"model\":\"syn-1017\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"ok)\"},\"finish_reason\":\"stop\"}]}\n\n"
        "data: {\"id\":\"s1\",\"model\":\"syn-1017\",\"choices\":[],\"usage\":{\"prompt_tokens\":7,\"completion_tokens\":3,\"total_tokens\":10}}\n\n"
        "data: [DONE]\n\n")

fn ! sendChunks! fd: Int64 cs: (List String) pauseMs: Int64 -> Bool
  (match (listHead cs)
    ((none) true)
    ((some c)
      (if (not (writeAll! fd c)) false
        (do (sleepMs (if (stringStartsWith? c ": ") pauseMs 0))
            (sendChunks! fd (optionOr (listTail cs) (list)) pauseMs)))))

fn ! answer! fd: Int64 raw: String pauseMs: Int64 -> Bool
  (if (stringContains? (stringReplace raw " " "") "\"stream\":true")
    (and (writeAll! fd "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n")
         (sendChunks! fd (chunks) pauseMs))
    (let [(body "{\"error\":{\"message\":\"this model requires stream=true\",\"type\":\"invalid_request_error\"}}")]
      (writeAll! fd (str "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(portFile (optionOr (listGet args 0) ""))
        (seenFile (optionOr (listGet args 1) ""))
        (pauseMs (optionOr (stringToInt64 (optionOr (listGet args 2) "")) 1000))
        (deadlineSec (optionOr (stringToInt64 (optionOr (listGet args 3) "")) 30))]
    (match (tcpListen 0)
      ((err e) (err (str "tcpListen: " e)))
      ((ok listener)
        (match (sockLocalPort listener)
          ((err e) (err (str "sockLocalPort: " e)))
          ((ok port)
            (let [(_ (fileWrite (str portFile ".tmp") (str (stringFromInt64 port) "\n")))
                  (_2 (pathRename (str portFile ".tmp") portFile))]
              (match (fdPoll (list (pair listener 1)) (* deadlineSec 1000))
                ((err e) (err (str "poll: " e)))
                ((ok ready)
                  (if (listEmpty? ready) (ok 2)
                    (match (sockAccept listener)
                      ((err e) (err (str "accept: " e)))
                      ((ok fd)
                        (let [(raw (readRequest! fd (+ (nowMs!) 10000) ""))
                              (_3 (fileWrite seenFile raw))
                              (sent (answer! fd raw pauseMs))
                              (_4 (fdClose fd))]
                          (ok (if sent 0 1))))))))))))))
