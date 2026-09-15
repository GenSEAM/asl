(module asl-sh/watchdogTest
  :d "Unit tests for watchdog port bound detection and port number parsing."
  :x [runTests]
  :i [(watchdog :a wd)])

(df testParsePortNumberValid [] -> Bool
  :d "Verifies that parsePortNumber correctly parses valid numeric ports."
  (let [(p1 (wd/parsePortNumber "3000"))
        (p2 (wd/parsePortNumber "8080"))
        (p3 (wd/parsePortNumber "1"))
        (p4 (wd/parsePortNumber "65535"))
        (p5 (wd/parsePortNumber "5173/tcp"))
        (p6 (wd/parsePortNumber " 8000 \n"))]
    (assert (= p1 (some 3000)) "Port 3000 parsed")
    (assert (= p2 (some 8080)) "Port 8080 parsed")
    (assert (= p3 (some 1)) "Port 1 (min) parsed")
    (assert (= p4 (some 65535)) "Port 65535 (max) parsed")
    (assert (= p5 (some 5173)) "Port 5173 with trailing chars parsed")
    (assert (= p6 (some 8000)) "Trimmed port 8000 parsed")
    true))

(df testParsePortNumberInvalid [] -> Bool
  :d "Verifies that parsePortNumber rejects invalid, out-of-range, or non-numeric strings."
  (let [(p0 (wd/parsePortNumber "0"))
        (pNeg (wd/parsePortNumber "-1"))
        (pTooHigh (wd/parsePortNumber "65536"))
        (pHuge (wd/parsePortNumber "999999"))
        (pEmpty (wd/parsePortNumber ""))
        (pLetters (wd/parsePortNumber "abc"))
        (pLeadingLetters (wd/parsePortNumber "port3000"))]
    (assert (= p0 (none)) "Port 0 rejected")
    (assert (= pNeg (none)) "Negative port rejected")
    (assert (= pTooHigh (none)) "Port 65536 rejected")
    (assert (= pHuge (none)) "Port 999999 rejected")
    (assert (= pEmpty (none)) "Empty port string rejected")
    (assert (= pLetters (none)) "Alphabetic port rejected")
    (assert (= pLeadingLetters (none)) "Leading letters port rejected")
    true))

(df testDetectBoundPortDirect [] -> Bool
  :d "Verifies detection of :port-bound log markers."
  (let [(v1 (wd/detectBoundPort ":port-bound 3000"))
        (v2 (wd/detectBoundPort "daemon started :port-bound 8080 ok"))
        (vFail (wd/detectBoundPort ":port-bound abc"))
        (vOor (wd/detectBoundPort ":port-bound 70000"))]
    (assert (.-detected v1) ":port-bound 3000 detected")
    (assert (= (.-port v1) 3000) "Port matches 3000")
    (assert (= (.-event v1) ":port-bound") "Event matches :port-bound")
    (assert (.-detected v2) "Embedded :port-bound 8080 detected")
    (assert (= (.-port v2) 8080) "Port matches 8080")
    (refute (.-detected vFail) "Invalid :port-bound rejected")
    (assert (= (.-port vFail) 0) "Invalid :port-bound port 0")
    (assert (= (.-event vFail) ":none") "Invalid :port-bound event :none")
    (refute (.-detected vOor) "Out-of-range :port-bound rejected")
    true))

(df testDetectBoundPortPatterns [] -> Bool
  :d "Verifies detection of standard server listening log patterns."
  (let [(vListen (wd/detectBoundPort "Server listening on port 8080"))
        (vHost (wd/detectBoundPort "Ready at http://localhost:5173/"))
        (vIp1 (wd/detectBoundPort "Serving HTTP on 127.0.0.1:8000 ..."))
        (vIp0 (wd/detectBoundPort "Bound to 0.0.0.0:4000"))
        (vIpv6Loop (wd/detectBoundPort "Listening on [::1]:9000"))
        (vIpv6Any (wd/detectBoundPort "Bound to [::]:8080"))
        (vNone (wd/detectBoundPort "Compiling main.rs: 42 modules processed"))]
    (assert (.-detected vListen) "Listening on port 8080 detected")
    (assert (= (.-port vListen) 8080) "Port matches 8080")
    (assert (.-detected vHost) "Localhost:5173 detected")
    (assert (= (.-port vHost) 5173) "Port matches 5173")
    (assert (.-detected vIp1) "127.0.0.1:8000 detected")
    (assert (= (.-port vIp1) 8000) "Port matches 8000")
    (assert (.-detected vIp0) "0.0.0.0:4000 detected")
    (assert (= (.-port vIp0) 4000) "Port matches 4000")
    (assert (.-detected vIpv6Loop) "[::1]:9000 detected")
    (assert (= (.-port vIpv6Loop) 9000) "Port matches 9000 for [::1]")
    (assert (.-detected vIpv6Any) "[::]:8080 detected")
    (assert (= (.-port vIpv6Any) 8080) "Port matches 8080 for [::]")
    (refute (.-detected vNone) "Unrelated log line rejected")
    (assert (= (.-port vNone) 0) "Unrelated line has port 0")
    (assert (= (.-event vNone) ":none") "Unrelated line has event :none")
    true))

(df runTests [] -> Bool
  :d "Runs all watchdog unit tests."
  (and (testParsePortNumberValid)
       (and (testParsePortNumberInvalid)
            (and (testDetectBoundPortDirect)
                 (testDetectBoundPortPatterns)))))
