(module asl-engine/transport
  :x [chooseTransport! transportField engineSocketPath! runEngineCommand! runEngineEval!
      socketErrorText! readFrame! writeAllFd! socketExchange!]
  :i [(asl-engine/wire :a w)])

fn engineSocketPath! rootDir: String -> String
  (let [(envSock (optionOr (envGet "ASL_ENGINE_SOCKET") ""))]
    (if (!= envSock "")
      envSock
      (str rootDir "/.asl/engine.sock")))

fn chooseTransport! envVal: String sockPath: String -> (Pair String String)
  (cond
    ((= envVal "subprocess")
      (pair "subprocess" "ASL_TRANSPORT=subprocess"))
    ((not (ok? (fileStat sockPath)))
      (pair "subprocess" (str "no engine socket at " sockPath)))
    (else
      (pair "subprocess" (str "socket transport is not implemented by this package; subprocess fallback for socket at " sockPath))))

fn transportField mode: String why: String -> String
  (str ":transport :" mode (if (!= why "") (str " :transportWhy \"" (w/escapeStr why) "\"") ""))

fn runEngineCommand! engineBin: String args: (List String) -> ProcessOutput
  (let [(argStr (stringJoin args " "))
        (fullCmd (str engineBin " " argStr))]
    (processRun fullCmd))

fn runEngineEval! aslBin: String expr: String -> ProcessOutput
  (let [(fullCmd (str aslBin " eval '" expr "'"))]
    (processRun fullCmd))

fn errnoName darwin: Bool n: Int64 -> String
  (cond
    ((= n 2) "No such file or directory")
    ((= n 13) "Permission denied")
    ((= n 20) "Not a directory")
    ((= n 22) "Invalid argument")
    ((= n 32) "Broken pipe")
    ((and darwin (= n 35)) "Resource temporarily unavailable")
    ((and darwin (= n 38)) "Socket operation on non-socket")
    ((and darwin (= n 54)) "Connection reset by peer")
    ((and darwin (= n 61)) "Connection refused")
    ((and darwin (= n 63)) "File name too long")
    ((and (not darwin) (= n 11)) "Resource temporarily unavailable")
    ((and (not darwin) (= n 36)) "File name too long")
    ((and (not darwin) (= n 88)) "Socket operation on non-socket")
    ((and (not darwin) (= n 104)) "Connection reset by peer")
    ((and (not darwin) (= n 111)) "Connection refused")
    (else ""))

fn socketErrorText! code: String -> String
  (let [(n (if (stringStartsWith? code "io:") (optionOr (stringToInt64 (optionOr (stringSlice code 3 (stringLength code)) "")) -1) -1))
        (darwin (mt (platformInfo) ((ok p) (= p.os "Darwin")) ((err _) false)))
        (name (if (< n 0) "" (errnoName darwin n)))]
    (if (stringEmpty? name) code (str "[Errno " (stringFromInt64 n) "] " name)))

fn leftMs! deadline: Int64 -> Int64
  (max 0 (/ (- deadline (monotonicNs)) 1000000))

fn ! readFrame! fd: Int64 acc: String deadline: Int64 limit: Int64 -> (Result String String)
  (mt (stringIndexOf acc "\n")
    ((some i) (ok (optionOr (stringSlice acc 0 i) "")))
    ((none)
      (cond
        ((> (stringLength acc) limit) (err (str "frame exceeds " (stringFromInt64 limit) " bytes")))
        ((= (leftMs! deadline) 0) (err "timed out"))
        (else
          (mt (fdPoll (list (pair fd 1)) (leftMs! deadline))
            ((err e) (err (socketErrorText! e)))
            ((ok ready)
              (if (listEmpty? ready)
                (err "timed out")
                (mt (fdRead fd 65536)
                  ((err e) (err (socketErrorText! e)))
                  ((ok chunk)
                    (if (stringEmpty? chunk)
                      (err "the engine closed the connection before its answer ended")
                      (readFrame! fd (stringConcat acc chunk) deadline limit)))))))))))

fn ! writeAllFd! fd: Int64 data: String -> (Result Unit String)
  (if (stringEmpty? data)
    (ok ())
    (mt (fdWrite fd data)
      ((err e) (err (socketErrorText! e)))
      ((ok n)
        (if (<= n 0)
          (err "the peer accepted no bytes")
          (writeAllFd! fd (optionOr (stringSlice data n (stringLength data)) ""))))))

fn ! socketExchange! sockPath: String line: String timeoutMs: Int64 -> (Result String String)
  (mt (unixConnect sockPath)
    ((err e) (err (socketErrorText! e)))
    ((ok fd)
      (let [(deadline (+ (monotonicNs) (* (max 1 timeoutMs) 1000000)))
            (answer (mt (writeAllFd! fd (str line "\n"))
                      ((err e) (err e))
                      ((ok _) (readFrame! fd "" deadline 8388608))))
            (_ (fdClose fd))]
        answer)))
