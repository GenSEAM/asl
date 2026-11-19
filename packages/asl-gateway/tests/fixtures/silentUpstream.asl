(module aslGateway/tests/fixtures/silentUpstream
  :x [main]
  :i [])

; (:m :ref TLE-2-PROVIDER-WAIT :do "stand-in for a provider that goes quiet: bin/asl run silentUpstream.asl PORTFILE SEENFILE STOPFILE DEADLINESEC listens on a free port, writes it to PORTFILE and serves every connection until STOPFILE exists (exit 0) or DEADLINESEC passes (exit 2). The model name of a request picks the behaviour: silent and mute read the request and never answer; stall sends the SSE head and one chunk and then nothing; slowStream sends its chunks with 1200 ms between them; anything else answers a plain completion at once. SEENFILE holds one model name per request, in arrival order")

(schema Conn
  (:f fd Int64)
  (:f raw String)
  (:f held Bool)
  (:f left (List String))
  (:f nextMs Int64))

(schema Live
  (:f conns (List Conn))
  (:f seen (List String)))

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

fn modelOf raw: String -> String
  (let [(flat (stringReplace raw " " ""))
        (mark "\"model\":\"")]
    (match (stringIndexOf flat mark)
      ((none) "")
      ((some at)
        (let [(rest (optionOr (stringSlice flat (+ at (stringLength mark)) (stringLength flat)) ""))]
          (optionOr (stringSlice rest 0 (optionOr (stringIndexOf rest "\"") 0)) "")))))

fn sseHead -> String
  "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"

fn delta model: String text: String finish: String -> String
  (str "data: {\"id\":\"s\",\"model\":\"" model "\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"" text "\"},\"finish_reason\":" finish "}]}\n\n")

fn slowChunks model: String -> (List String)
  (list (delta model "served:" "null")
        (delta model "slow" "null")
        (delta model "Stream" "\"stop\"")
        (str "data: {\"id\":\"s\",\"model\":\"" model "\",\"choices\":[],\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":3,\"total_tokens\":5}}\n\ndata: [DONE]\n\n"))

fn plain model: String -> String
  (let [(body (str "{\"id\":\"p\",\"object\":\"chat.completion\",\"model\":\"" model "\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"served:" model "\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}"))]
    (str "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))

; (:m :do "a complete request is answered by its model's behaviour; a held connection stays open and silent until the fixture ends")
fn ! answer! c: Conn model: String -> (Option Conn)
  (cond
    ((or (= model "silent") (= model "mute")) (some (with c :held true)))
    ((= model "stall") (do (writeAll! c.fd (str (sseHead) (delta model "half" "null"))) (some (with c :held true))))
    ((= model "slowStream") (do (writeAll! c.fd (sseHead)) (some (with c :held true :left (slowChunks model) :nextMs (+ (nowMs!) 1200)))))
    (else (do (writeAll! c.fd (plain model)) (fdClose c.fd) none)))

fn ! stepHeld! c: Conn -> (Option Conn)
  (match (listHead c.left)
    ((none) (some c))
    ((some chunk)
      (if (< (nowMs!) c.nextMs) (some c)
        (let [(rest (optionOr (listTail c.left) (list)))]
          (do (writeAll! c.fd chunk)
            (if (listEmpty? rest) (do (fdClose c.fd) none) (some (with c :left rest :nextMs (+ (nowMs!) 1200)))))))))

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(x (Pair Int64 Int64))] -> Bool (= (pairFirst x) fd)) ready)

fn ! stepConn! live: Live c: Conn ready: (List (Pair Int64 Int64)) seenFile: String -> Live
  (let [(keep (fn [(x (Option Conn))] -> Live (match x ((some k) (with live :conns (listAppend live.conns (list k)))) ((none) live))))]
    (if c.held (keep (stepHeld! c))
      (if (not (ready? ready c.fd)) (keep (some c))
        (match (fdRead c.fd 65536)
          ((err _) (do (fdClose c.fd) live))
          ((ok chunk)
            (if (stringEmpty? chunk) (do (fdClose c.fd) live)
              (let [(raw (str c.raw chunk))]
                (if (not (requestDone? raw)) (keep (some (with c :raw raw)))
                  (let [(model (modelOf raw))
                        (seen (listAppend live.seen (list model)))
                        (_ (fileWrite seenFile (str (stringJoin seen "\n") "\n")))
                        (next (answer! (with c :raw raw) model))]
                    (match next
                      ((some k) (Live :conns (listAppend live.conns (list k)) :seen seen))
                      ((none) (with live :seen seen))))))))))))

fn ! closeAll! live: Live -> Bool
  (listAll? (fn [(c Conn)] -> Bool (do (fdClose c.fd) true)) live.conns)

fn ! serve! listener: Int64 live: Live seenFile: String stopFile: String deadlineMs: Int64 -> Int64
  (cond
    ((fileExists? stopFile) (do (closeAll! live) 0))
    ((>= (nowMs!) deadlineMs) (do (closeAll! live) 2))
    (else
      (let [(watch (cons (pair listener 1) (map (fn [(c Conn)] -> (Pair Int64 Int64) (pair c.fd 1)) (filter (fn [(c Conn)] -> Bool (not c.held)) live.conns))))
            (ready (resultOr (fdPoll watch 50) (list)))
            (accepted (if (ready? ready listener)
                        (match (sockAccept listener)
                          ((ok fd) (with live :conns (listAppend live.conns (list (Conn :fd fd :raw "" :held false :left (list) :nextMs 0)))))
                          ((err _) live))
                        live))
            (next (fold (fn [(acc Live) (c Conn)] -> Live (stepConn! acc c ready seenFile)) (with accepted :conns (list)) accepted.conns))]
        (serve! listener next seenFile stopFile deadlineMs))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(portFile (optionOr (listGet args 0) ""))
        (seenFile (optionOr (listGet args 1) ""))
        (stopFile (optionOr (listGet args 2) ""))
        (deadlineSec (optionOr (stringToInt64 (optionOr (listGet args 3) "")) 60))]
    (if (or (stringEmpty? portFile) (or (stringEmpty? seenFile) (stringEmpty? stopFile)))
      (err "usage: silentUpstream.asl PORTFILE SEENFILE STOPFILE DEADLINESEC")
      (match (tcpListen 0)
        ((err e) (err (str "tcpListen: " e)))
        ((ok listener)
          (match (sockLocalPort listener)
            ((err e) (do (fdClose listener) (err (str "sockLocalPort: " e))))
            ((ok port)
              (let [(_ (fileWrite (str portFile ".tmp") (str (stringFromInt64 port) "\n")))
                    (_2 (pathRename (str portFile ".tmp") portFile))
                    (code (serve! listener (Live :conns (list) :seen (list)) seenFile stopFile (+ (nowMs!) (* deadlineSec 1000))))
                    (_3 (fdClose listener))]
                (ok code))))))))
