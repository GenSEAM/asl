(module asl/agentLoop/tests/holdHubStub
  :x [main]
  :i [])

; (:m :ref SE5D-POOL-E2E :do "stand-in hub for a pool process, run as a bounded child: listens on the unix socket in argv 1, holds every complete request for argv 3 ms before answering the two scripted model replies of the edit fixture (the first write, then the second write and done, picked by whether the request already carries the first), and keeps the file in argv 2 current: a maxInFlight line (most requests held at once) and one profile line per request with the X-ASL-Profile it carried")
(schema Conn
  (:f fd Int64)
  (:f input String)
  (:f replyAt Int64)
  (:f reply String))

(schema St
  (:f listener Int64)
  (:f conns (List Conn))
  (:f peak Int64)
  (:f profiles (List String)))

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(r (Pair Int64 Int64))] -> Bool (= (pairFirst r) fd)) ready)

fn contentLength head: String -> Int64
  (fold (fn [(acc Int64) (line String)] -> Int64
          (if (stringStartsWith? (stringLower line) "content-length:")
            (optionOr (stringToInt64 (stringTrim (optionOr (stringSlice line 15 (stringLength line)) ""))) acc) acc))
    0 (stringSplit head "\r\n"))

fn complete? raw: String -> Bool
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) false)
    ((some end) (>= (- (stringLength raw) (+ end 4)) (contentLength (optionOr (stringSlice raw 0 end) "")))))

fn asnQuote text: String -> String
  (stringReplace (stringReplace text "\\" "\\\\") "\"" "\\\"")

fn stepOne -> String
  "(:step :op \"write\" :file \"subject.txt\" :content \"blue\\n\")"

fn stepTwo -> String
  "(:step :op \"write\" :file \"subject.txt\" :content \"green\\n\") (:done)"

fn replyFor input: String -> String
  (let [(content (asnQuote (if (stringContains? input "blue") (stepTwo) (stepOne))))
        (body (str "(:reply :content \"" content "\")"))]
    (str "HTTP/1.1 200 OK\r\nContent-Type: application/asn+sexpr\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))

fn profileOf input: String -> String
  (let [(low (stringLower input))]
    (match (stringIndexOf low "x-asl-profile:")
      ((none) "none")
      ((some at)
        (let [(rest (optionOr (stringSlice input (+ at 14) (stringLength input)) ""))]
          (stringTrim (optionOr (listHead (stringSplit rest "\r\n")) ""))))))

fn held st: St -> Int64
  (listLength (filter (fn [(c Conn)] -> Bool (> c.replyAt 0)) st.conns))

fn ! stepConn! st: St c: Conn ready: (List (Pair Int64 Int64)) holdMs: Int64 -> St
  (cond
    ((> c.replyAt 0)
      (if (>= (nowMs!) c.replyAt)
        (do (fdWrite c.fd c.reply) (fdClose c.fd) st)
        (with st :conns (listAppend st.conns (list c)))))
    ((not (ready? ready c.fd)) (with st :conns (listAppend st.conns (list c))))
    (else
      (match (fdRead c.fd 65536)
        ((err _) (do (fdClose c.fd) st))
        ((ok chunk)
          (if (stringEmpty? chunk) (do (fdClose c.fd) st)
            (let [(input (str c.input chunk))]
              (if (complete? input)
                (with st :conns (listAppend st.conns (list (Conn :fd c.fd :input input :replyAt (+ (nowMs!) holdMs) :reply (replyFor input)))) :profiles (listAppend st.profiles (list (profileOf input))))
                (with st :conns (listAppend st.conns (list (Conn :fd c.fd :input input :replyAt 0 :reply "")))))))))))

fn ! loop! st: St out: String holdMs: Int64 -> Bool
  (match (fdPoll (cons (pair st.listener 1) (map (fn [(c Conn)] -> (Pair Int64 Int64) (pair c.fd 1)) st.conns)) 20)
    ((err _) (loop! st out holdMs))
    ((ok ready)
      (let [(accepted (if (ready? ready st.listener)
                        (match (sockAccept st.listener)
                          ((ok fd) (with st :conns (listAppend st.conns (list (Conn :fd fd :input "" :replyAt 0 :reply ""))))) 
                          ((err _) st))
                        st))
            (stepped (fold (fn [(acc St) (c Conn)] -> St (stepConn! acc c ready holdMs)) (with accepted :conns (list)) accepted.conns))
            (peaked (with stepped :peak (max stepped.peak (held stepped))))
            (written (fileWrite out (str "maxInFlight " (stringFromInt64 peaked.peak) "\n" (stringJoin (map (fn [(p String)] -> String (str "profile " p)) peaked.profiles) "\n") "\n")))]
        (loop! peaked out holdMs))))

fn ! main args: (List String) -> (Result Int64 String)
  (match (unixListen (optionOr (listGet args 0) ""))
    ((err e) (err e))
    ((ok listener)
      (do (loop! (St :listener listener :conns (list) :peak 0 :profiles (list)) (optionOr (listGet args 1) "") (optionOr (stringToInt64 (optionOr (listGet args 2) "1500")) 1500))
        (ok 0))))
