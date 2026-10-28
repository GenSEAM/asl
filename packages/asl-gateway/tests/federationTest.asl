(module aslGateway/tests/federationTest
  :x [runTests]
  :i [(federation :a f) (secrets :a s) (upstream :a u)])

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

fn httpReply status: Int64 reason: String body: String -> String
  (str "HTTP/1.1 " (stringFromInt64 status) " " reason "\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)

fn ! serveOnce! listener: Int64 expectToken: String echo: Bool -> String
  (let [(ready (fdPoll (list (pair listener 1)) 10000))]
    (match ready
      ((err _) "")
      ((ok r)
        (if (listEmpty? r) ""
          (match (sockAccept listener)
            ((err _) "")
            ((ok fd)
              (let [(raw (readRequest! fd (+ (nowMs!) 10000) ""))
                    (auth (headValue raw "Authorization"))
                    (good (= auth (str "Bearer " expectToken)))
                    (reply (cond
                             (good (httpReply 200 "OK" "{\"choices\":[{\"message\":{\"content\":\"from-mac\"}}]}"))
                             (echo (httpReply 401 "Unauthorized" (str "{\"error\":\"bad token " (stringReplace auth "Bearer " "") "\"}")))
                             (else (httpReply 401 "Unauthorized" "{\"error\":\"unauthorized\"}"))))
                    (_ (writeAll! fd reply))
                    (_2 (fdClose fd))]
                raw)))))))

fn ! scratch! -> String
  (let [(d (str "/tmp/gwFederationTest-" (procSelf) "-" (nowNs)))
        (_ (dirCreate d))]
    d)

fn ! drop! dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))
        (_ (map (fn [(n String)] -> Bool (ok? (pathRemove (str dir "/" n)))) names))]
    (ok? (pathRemove dir)))

fn ! storeOf! dir: String -> (Result s/SecretStore String)
  (let [(p (str dir "/secrets.asn"))
        (_ (fileWrite p "(:secret :id macToken :value \"tok-MAC-7f3a9c21\")\n(:secret :id wrongToken :value \"tok-WRONG-55d0e8b4\")\n"))
        (_2 (fileChmod p 384))]
    (s/secretsLoad! p))

fn env -> (Map String String)
  (mapFromPairs (list (pair "PATH" (optionOr (envGet "PATH") "/usr/bin:/bin"))))

fn rg port: Int64 secret: String -> f/RemoteGateway
  (f/RemoteGateway :id "mac" :base (str "http://127.0.0.1:" (stringFromInt64 port)) :secret secret)

fn body -> String
  "{\"model\":\"agyFlash\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"

fn hdrs -> (List (Pair String String))
  (list (pair "X-ASL-Session" "sess-abc123"))

fn ! feedStdin! call: u/UpstreamCall rounds: Int64 -> u/UpstreamCall
  (if (or (<= rounds 0) (not call.pipe.inOpen)) call
    (match (fdPoll (u/upstreamCallWatch call) 200)
      ((err _) call)
      ((ok ready)
        (match (u/upstreamCallPump! call ready)
          ((err _) call)
          ((ok next) (feedStdin! next (- rounds 1)))))))

fn ! exchange! store: s/SecretStore secret: String expect: String echo: Bool -> (Pair String String)
  (let [(listener (resultOr (tcpListen 0) -1))
        (port (resultOr (sockLocalPort listener) 0))
        (started (f/remoteStart! store (rg port secret) (body) (hdrs) (env) 20.0))]
    (match started
      ((err e) (do (fdClose listener) (pair e "")))
      ((ok call)
        (let [(fed (feedStdin! call 50))
              (seen (serveOnce! listener expect echo))
              (receipt (f/remoteFinish! store (rg port secret) fed 20.0))
              (_ (fdClose listener))]
          (pair receipt seen)))))

fn ! runTests -> Bool
  (let [(dir (scratch!))]
    (match (storeOf! dir)
      ((err e) (do (assert false (str "temp secrets load: " e)) false))
      ((ok store)
        (let [(good (exchange! store "macToken" "tok-MAC-7f3a9c21" false))
              (bad (exchange! store "wrongToken" "tok-MAC-7f3a9c21" false))
              (echoed (exchange! store "wrongToken" "tok-MAC-7f3a9c21" true))
              (missing (f/remoteForward! store (rg 1 "noSuchSecret") (body) (hdrs) (env) 5.0))
              (dead (let [(l (resultOr (tcpListen 0) -1))
                          (p (resultOr (sockLocalPort l) 0))
                          (_ (fdClose l))]
                      (f/remoteForward! store (rg p "macToken") (body) (hdrs) (env) 5.0)))
              (all (str (pairFirst good) (pairFirst bad) (pairFirst echoed) missing dead))
              (_ (drop! dir))]
          (do
            (assert (stringStartsWith? (pairFirst good) "(:remoteReply :provider mac :status 200") (str "the remote gateway reply comes back as ASN: " (pairFirst good)))
            (assert (stringContains? (pairFirst good) "from-mac") "the reply body is the second gateway's")
            (assert (stringContains? (pairSecond good) "Authorization: Bearer tok-MAC-7f3a9c21") "the second gateway saw the bearer read from the secrets file with no env var set")
            (assert (stringContains? (pairSecond good) "agyFlash") "the request body is forwarded")
            (assert (stringContains? (stringLower (pairSecond good)) "x-asl-session: sess-abc123") "the session header is forwarded")
            (assert (stringContains? (pairFirst bad) "(:err :code ERR_REMOTE_HTTP :provider mac :status 401") (str "a rejected token is an ASN error: " (pairFirst bad)))
            (assert (stringContains? (pairFirst echoed) "ERR_REMOTE_HTTP") "an echoing second gateway still yields an error receipt")
            (assert (stringContains? (pairFirst echoed) "<secret:wrongToken>") "the echoed token is redacted to its id")
            (assert (stringContains? missing "ERR_SECRET_MISSING") "a missing secret id fails before any connection")
            (assert (stringContains? missing "noSuchSecret") "the receipt names the id")
            (assert (stringContains? dead "ERR_REMOTE_TRANSPORT") (str "an unreachable second gateway is a transport error: " dead))
            (assert (not (stringContains? all "tok-MAC-7f3a9c21")) "no receipt contains the mac token")
            (assert (not (stringContains? all "tok-WRONG-55d0e8b4")) "no receipt contains the wrong token")
            (assert (err? (f/federationAuth (list) "tok")) "no bearer is 401")
            (assert (err? (f/federationAuth (list (pair "Authorization" "Bearer nope")) "tok")) "a wrong bearer is 401")
            (assert (ok? (f/federationAuth (list (pair "authorization" "Bearer tok")) "tok")) "the right bearer passes")
            (assert (err? (f/federationAuth (list (pair "Authorization" "Bearer ")) "")) "an empty expected token never authenticates")
            true)))))
