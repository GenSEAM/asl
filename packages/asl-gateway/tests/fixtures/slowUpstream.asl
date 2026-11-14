(module aslGateway/tests/fixtures/slowUpstream
  :x [main]
  :i [])

; (:m :ref GW-LINK-CORRELATION :do "stand-in chat upstream for linkCorrelationTest: bin/asl run slowUpstream.asl PORTFILE SLOWMS MAXREQUESTS DEADLINESEC listens on a free port, writes it to PORTFILE and answers requests one after another; the reply content is ans: plus the word after MARK- in the request, and only the first request waits SLOWMS before its answer; it exits after MAXREQUESTS answers or at the deadline")

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

fn wordChar? c: String -> Bool
  (or (and (>= c "a") (<= c "z")) (or (and (>= c "A") (<= c "Z")) (and (>= c "0") (<= c "9"))))

fn tailrec wordEnd text: String i: Int64 -> Int64
  (if (and (< i (stringLength text)) (wordChar? (optionOr (stringSlice text i (+ i 1)) ""))) (wordEnd text (+ i 1)) i)

fn markOf raw: String -> String
  (match (stringIndexOf raw "MARK-")
    ((none) "none")
    ((some at) (optionOr (stringSlice raw (+ at 5) (wordEnd raw (+ at 5))) "none")))

fn ! answer! fd: Int64 raw: String -> Bool
  (let [(body (str "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"plain-1\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"ans:" (markOf raw)
                   "\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":7,\"completion_tokens\":3,\"total_tokens\":10}}"))]
    (writeAll! fd (str "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)))

fn ! serve! listener: Int64 served: Int64 maxRequests: Int64 slowMs: Int64 deadline: Int64 -> Int64
  (if (or (>= served maxRequests) (>= (nowMs!) deadline)) served
    (match (fdPoll (list (pair listener 1)) 200)
      ((err _) served)
      ((ok ready)
        (if (listEmpty? ready) (serve! listener served maxRequests slowMs deadline)
          (match (sockAccept listener)
            ((err _) served)
            ((ok fd)
              (let [(raw (readRequest! fd (+ (nowMs!) 5000) ""))
                    (waited (if (= served 0) (sleepMs slowMs) (sleepMs 0)))
                    (sent (answer! fd raw))
                    (closed (fdClose fd))]
                (serve! listener (+ served 1) maxRequests slowMs deadline))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(portFile (optionOr (listGet args 0) ""))
        (slowMs (optionOr (stringToInt64 (optionOr (listGet args 1) "")) 1500))
        (maxRequests (optionOr (stringToInt64 (optionOr (listGet args 2) "")) 3))
        (deadlineSec (min 60 (optionOr (stringToInt64 (optionOr (listGet args 3) "")) 20)))]
    (match (tcpListen 0)
      ((err e) (err (str "tcpListen: " e)))
      ((ok listener)
        (match (sockLocalPort listener)
          ((err e) (err (str "sockLocalPort: " e)))
          ((ok port)
            (let [(wrote (fileWrite (str portFile ".tmp") (str (stringFromInt64 port) "\n")))
                  (moved (pathRename (str portFile ".tmp") portFile))
                  (served (serve! listener 0 maxRequests slowMs (+ (nowMs!) (* deadlineSec 1000))))]
              (ok 0)))))))
