(module asl-tools/coord/tests/fixtures/hubStatusStub
  :x [main]
  :i [])

; (:m :ref LANE-UNAVAILABLE-MEMORY-FIX :do "variant of hubVerdictStub: a reply file that starts with HTTP followed by a status code and a raw body answers that status with that body verbatim (a provider JSON error), any other text is answered 200 as before; every request is appended to the log")
fn bodyComplete? raw: String -> Bool
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) false)
    ((some end)
      (let [(head (stringLower (optionOr (stringSlice raw 0 end) "")))
            (want (match (stringIndexOf head "content-length:")
                    ((none) 0)
                    ((some at) (optionOr (stringToInt64 (stringTrim (optionOr (listHead (stringSplit (optionOr (stringSlice head (+ at 15) (stringLength head)) "") "\r\n")) ""))) 0))))]
        (>= (- (stringLength raw) (+ end 4)) want))))

fn ! readRequest! fd: Int64 acc: String -> String
  (if (bodyComplete? acc) acc
    (match (fdRead fd 65536)
      ((err _) acc)
      ((ok chunk) (if (stringEmpty? chunk) acc (readRequest! fd (str acc chunk))))))

fn esc s: String -> String
  (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" " ")

; (:m :ref PIPE-GATES :do "the stub bounds itself: it polls the listener 100 ms at a time and returns when the deadline (arg 3, seconds, default 600) has passed or the request cap (arg 4, default 50) is served, so a test that dies between startHub! and stopHub! leaves no hub behind")
fn ! serve! listener: Int64 out: String replyFile: String deadlineMs: Int64 left: Int64 -> (Result Int64 String)
  (if (or (<= left 0) (>= (/ (monotonicNs) 1000000) deadlineMs)) (ok 0)
    (match (fdPoll (list (pair listener 1)) 100)
      ((err e) (err e))
      ((ok ready)
        (if (listEmpty? ready) (serve! listener out replyFile deadlineMs left)
          (match (sockAccept listener)
            ((err e) (err e))
            ((ok conn)
              (let [(req (readRequest! conn ""))
                    (_ (fileAppend out (str req "\n----\n")))
                    (text (stringTrim (resultOr (fileReadString replyFile) "")))
                    (isErr (stringStartsWith? text "HTTP "))
                    (code (if isErr (optionOr (listGet (stringSplit text " ") 1) "500") "200"))
                    (body (if isErr (stringTrim (optionOr (stringSlice text (+ 6 (stringLength code)) (stringLength text)) "")) (str "(:reply :content \"" (esc text) "\")")))
                    (_ (fdWrite conn (str "HTTP/1.1 " code " X\r\nContent-Type: " (if isErr "application/json" "application/asn+sexpr") "\r\nContent-Length: " (stringFromInt64 (bytesLength (stringToBytes body))) "\r\nConnection: close\r\n\r\n" body)))
                    (_ (fdClose conn))]
                (serve! listener out replyFile deadlineMs (- left 1)))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (match (unixListen (optionOr (listGet args 0) ""))
    ((err e) (err e))
    ((ok listener)
      (serve! listener (optionOr (listGet args 1) "") (optionOr (listGet args 2) "")
              (+ (/ (monotonicNs) 1000000) (* 1000 (optionOr (stringToInt64 (optionOr (listGet args 3) "600")) 600)))
              (optionOr (stringToInt64 (optionOr (listGet args 4) "50")) 50))))
