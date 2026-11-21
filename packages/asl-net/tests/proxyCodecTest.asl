(module asl-net/tests/proxyCodecTest
  :x [runTests]
  :i [(asl-net/proxy :a proxy)])

fn bytesEqualFrom a: Bytes b: Bytes i: Int64 n: Int64 -> Bool
  (if (>= i n)
    true
    (if (= (bytesGet a i) (bytesGet b i))
      (bytesEqualFrom a b (+ i 1) n)
      false))

fn bytesEqual a: Bytes b: Bytes -> Bool
  (if (!= (bytesLength a) (bytesLength b))
    false
    (bytesEqualFrom a b 0 (bytesLength a)))

fn fillBytes b: Bytes xs: (List Int64) i: Int64 n: Int64 -> Unit
  (if (>= i n)
    ()
    (do
      (bytesSet b i (optionOr (listGet xs i) 0))
      (fillBytes b xs (+ i 1) n)))

fn bytesOf xs: (List Int64) -> Bytes
  (let [(b (bytesAlloc (listLength xs)))]
    (do (fillBytes b xs 0 (listLength xs)) b))

fn testConnectRequestNoAuth -> Bool
  (let [(got (proxy/connectRequest "example.com" 443 none))
        (want "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n")]
    (do
      (assert (= got want) (str "connectRequest without auth: " got))
      true))

fn testConnectRequestAuth -> Bool
  (let [(got (proxy/connectRequest "example.com" 443 (some (pair "user" "pass"))))
        (want "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\nProxy-Authorization: Basic dXNlcjpwYXNz\r\n\r\n")]
    (do
      (assert (= got want) (str "connectRequest with auth: " got))
      true))

fn testParseConnectReply -> Bool
  (do
    (assert (match (proxy/parseConnectReply "HTTP/1.1 200 Connection established\r\n\r\n")
              ((ok c) (= c 200))
              ((err _) false)) "200 is ok")
    (assert (match (proxy/parseConnectReply "HTTP/1.1 407 Proxy Authentication Required\r\n\r\n")
              ((ok _) false)
              ((err e) (= e "407"))) "407 errs with the code")
    (assert (err? (proxy/parseConnectReply "HTTP/1.1 200 OK\r\n")) "incomplete headers err")
    true)

fn testSocks5Greeting -> Bool
  (do
    (assert (bytesEqual (proxy/socks5Greeting false) (bytesOf (list 5 1 0))) "greeting without auth")
    (assert (bytesEqual (proxy/socks5Greeting true) (bytesOf (list 5 2 0 2))) "greeting with auth")
    true)

fn testParseSocks5Choice -> Bool
  (do
    (assert (match (proxy/parseSocks5Choice (bytesOf (list 5 0))) ((ok m) (= m 0)) ((err _) false)) "no-auth choice")
    (assert (match (proxy/parseSocks5Choice (bytesOf (list 5 2))) ((ok m) (= m 2)) ((err _) false)) "user/pass choice")
    (assert (err? (proxy/parseSocks5Choice (bytesOf (list 5 255)))) "no acceptable methods errs")
    (assert (err? (proxy/parseSocks5Choice (bytesOf (list 5 1)))) "unoffered method 1 errs")
    (assert (err? (proxy/parseSocks5Choice (bytesOf (list 5 3)))) "unoffered method 3 errs")
    (assert (err? (proxy/parseSocks5Choice (bytesOf (list 5)))) "short choice errs")
    true)

fn testSocks5ConnectRequest -> Bool
  (let [(got (proxy/socks5ConnectRequest "example.com" 443))
        (want (bytesOf (list 5 1 0 3 11 101 120 97 109 112 108 101 46 99 111 109 1 187)))]
    (do
      (assert (bytesEqual got want) "socks5 connect request bytes for example.com:443")
      true))

fn repName rep: Int64 -> String
  (cond
    ((= rep 1) "general SOCKS server failure")
    ((= rep 2) "connection not allowed by ruleset")
    ((= rep 3) "network unreachable")
    ((= rep 4) "host unreachable")
    ((= rep 5) "connection refused")
    ((= rep 6) "TTL expired")
    ((= rep 7) "command not supported")
    ((= rep 8) "address type not supported")
    (else "unknown"))

fn testParseSocks5Reply -> Bool
  (do
    (assert (match (proxy/parseSocks5Reply (bytesOf (list 5 0 0 1 0 0 0 0 0 0))) ((ok r) (= r 0)) ((err _) false)) "REP 0 is ok")
    (assert (match (proxy/parseSocks5Reply (bytesOf (list 5 1 0 1 0 0 0 0 0 0))) ((ok _) false) ((err e) (= e (repName 1)))) "REP 1 named")
    (assert (match (proxy/parseSocks5Reply (bytesOf (list 5 2 0 1 0 0 0 0 0 0))) ((ok _) false) ((err e) (= e (repName 2)))) "REP 2 named")
    (assert (match (proxy/parseSocks5Reply (bytesOf (list 5 3 0 1 0 0 0 0 0 0))) ((ok _) false) ((err e) (= e (repName 3)))) "REP 3 named")
    (assert (match (proxy/parseSocks5Reply (bytesOf (list 5 4 0 1 0 0 0 0 0 0))) ((ok _) false) ((err e) (= e (repName 4)))) "REP 4 named")
    (assert (match (proxy/parseSocks5Reply (bytesOf (list 5 5 0 1 0 0 0 0 0 0))) ((ok _) false) ((err e) (= e (repName 5)))) "REP 5 named")
    (assert (match (proxy/parseSocks5Reply (bytesOf (list 5 6 0 1 0 0 0 0 0 0))) ((ok _) false) ((err e) (= e (repName 6)))) "REP 6 named")
    (assert (match (proxy/parseSocks5Reply (bytesOf (list 5 7 0 1 0 0 0 0 0 0))) ((ok _) false) ((err e) (= e (repName 7)))) "REP 7 named")
    (assert (match (proxy/parseSocks5Reply (bytesOf (list 5 8 0 1 0 0 0 0 0 0))) ((ok _) false) ((err e) (= e (repName 8)))) "REP 8 named")
    (assert (err? (proxy/parseSocks5Reply (bytesOf (list 5)))) "short reply errs")
    true)

fn ! runTests -> Bool
  (do
    (assert (testConnectRequestNoAuth) "testConnectRequestNoAuth passed")
    (assert (testConnectRequestAuth) "testConnectRequestAuth passed")
    (assert (testParseConnectReply) "testParseConnectReply passed")
    (assert (testSocks5Greeting) "testSocks5Greeting passed")
    (assert (testParseSocks5Choice) "testParseSocks5Choice passed")
    (assert (testSocks5ConnectRequest) "testSocks5ConnectRequest passed")
    (assert (testParseSocks5Reply) "testParseSocks5Reply passed")
    true)
