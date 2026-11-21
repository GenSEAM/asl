(module asl-net/proxy
  :x [connectRequest parseConnectReply socks5Greeting parseSocks5Choice socks5ConnectRequest parseSocks5Reply]
  :i [])

fn firstLine text: String -> String
  (match (stringIndexOf text "\r\n")
    ((none) text)
    ((some i) (optionOr (stringSlice text 0 i) text)))

fn connectRequest host: String port: Int64 auth: (Option (Pair String String)) -> String
  (let [(authority (str host ":" (stringFromInt64 port)))
        (authLine (match auth
                    ((none) "")
                    ((some creds)
                      (str "Proxy-Authorization: Basic "
                           (bytesToBase64 (stringToBytes (str (pairFirst creds) ":" (pairSecond creds))))
                           "\r\n"))))]
    (str "CONNECT " authority " HTTP/1.1\r\nHost: " authority "\r\n" authLine "\r\n"))

fn parseConnectReply text: String -> (Result Int64 String)
  (if (none? (stringIndexOf text "\r\n\r\n"))
    (err "ERR_PROXY_CONNECT_INCOMPLETE")
    (let [(parts (stringSplit (firstLine text) " "))
          (codeStr (optionOr (listGet parts 1) ""))]
      (match (stringToInt64 codeStr)
        ((none) (err "ERR_PROXY_CONNECT_STATUS"))
        ((some code) (if (= code 200) (ok code) (err (stringFromInt64 code)))))))

fn socks5Greeting auth: Bool -> Bytes
  (if auth
    (let [(b (bytesAlloc 4))]
      (do (bytesSet b 0 5) (bytesSet b 1 2) (bytesSet b 2 0) (bytesSet b 3 2) b))
    (let [(b (bytesAlloc 3))]
      (do (bytesSet b 0 5) (bytesSet b 1 1) (bytesSet b 2 0) b)))

fn parseSocks5Choice b: Bytes -> (Result Int64 String)
  (if (< (bytesLength b) 2)
    (err "ERR_SOCKS5_CHOICE_INCOMPLETE")
    (if (!= (bytesGet b 0) 5)
      (err "ERR_SOCKS5_CHOICE_VERSION")
      (let [(m (bytesGet b 1))]
        (cond
          ((= m 255) (err "ERR_SOCKS5_NO_ACCEPTABLE_METHODS"))
          ((= m 0) (ok m))
          ((= m 2) (ok m))
          (else (err "ERR_SOCKS5_UNSUPPORTED_METHOD"))))))

fn fillHost b: Bytes hb: Bytes i: Int64 n: Int64 -> Unit
  (if (>= i n)
    ()
    (do
      (bytesSet b (+ 5 i) (bytesGet hb i))
      (fillHost b hb (+ i 1) n)))

fn socks5ConnectRequest host: String port: Int64 -> Bytes
  (let [(hb (stringToBytes host))
        (n (bytesLength hb))
        (b (bytesAlloc (+ 7 n)))]
    (do
      (bytesSet b 0 5)
      (bytesSet b 1 1)
      (bytesSet b 2 0)
      (bytesSet b 3 3)
      (bytesSet b 4 n)
      (fillHost b hb 0 n)
      (bytesSet b (+ 5 n) (/ port 256))
      (bytesSet b (+ 6 n) (mod port 256))
      b))

fn socks5RepName rep: Int64 -> String
  (cond
    ((= rep 1) "general SOCKS server failure")
    ((= rep 2) "connection not allowed by ruleset")
    ((= rep 3) "network unreachable")
    ((= rep 4) "host unreachable")
    ((= rep 5) "connection refused")
    ((= rep 6) "TTL expired")
    ((= rep 7) "command not supported")
    ((= rep 8) "address type not supported")
    (else "unknown SOCKS5 reply"))

fn parseSocks5Reply b: Bytes -> (Result Int64 String)
  (if (< (bytesLength b) 2)
    (err "ERR_SOCKS5_REPLY_INCOMPLETE")
    (if (!= (bytesGet b 0) 5)
      (err "ERR_SOCKS5_REPLY_VERSION")
      (let [(rep (bytesGet b 1))]
        (if (= rep 0) (ok rep) (err (socks5RepName rep))))))
