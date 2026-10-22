(module asl-forms/tests/fixtures/fakeEngine :x [main] :i [(asl-forms/kernel :a k)])


fn readFrame! fd: Int64 acc: String -> (Result String String)
  (if (stringContains? acc "\n")
    (ok acc)
    (match (fdRead fd 4096)
      ((err e) (err e))
      ((ok chunk) (if (stringEmpty? chunk) (ok acc) (readFrame! fd (str acc chunk))))))

fn writeAll! fd: Int64 data: String from: Int64 -> (Result Int64 String)
  (if (>= from (stringLength data))
    (ok from)
    (match (fdWrite fd (optionOr (stringSlice data from (stringLength data)) ""))
      ((err e) (err e))
      ((ok n) (if (<= n 0) (err "no write progress") (writeAll! fd data (+ from n))))))

fn reply mode: String got: String -> String
  (cond
    ((= mode "ok") (str "(:engine :status :ok :got \"" (k/escapeAsnVal (stringTrim got)) "\")\n"))
    ((= mode "largeReply") (str "(:engine :status :ok :padding \"" (stringRepeat "x" 70000) "\")\n"))
    ((= mode "slowRead") (str "(:engine :status :ok :gotBytes " (stringFromInt64 (stringLength got)) ")\n"))
    ((= mode "reject") "(:receipt :status :error :message \"refused\")\n")
    (else "(:engine :status :ok :partial true"))

fn serve! listener: Int64 mode: String -> (Result Int64 String)
  (match (fdPoll (list (pair listener 1)) 10000)
    ((err e) (err e))
    ((ok ready) (if (listEmpty? ready) (err "no client within 10 s") (serveOne! listener mode))))

fn serveOne! listener: Int64 mode: String -> (Result Int64 String)
  (match (sockAccept listener)
    ((err e) (err e))
    ((ok conn)
      (let [(delay (if (= mode "slowRead") (sleepMs 200) (sleepMs 0)))
            (sent (match (readFrame! conn "") ((err e) (err e)) ((ok got) (writeAll! conn (reply mode got) 0))))
            (closed (fdClose conn))]
        (match sent ((err e) (err e)) ((ok _) (ok 0))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(path (optionOr (listHead args) ""))
        (mode (optionOr (listGet args 1) "ok"))]
    (match (unixListen path)
      ((err e) (err e))
      ((ok listener)
        (let [(served (serve! listener mode))
              (closed (fdClose listener))
              (removed (pathRemove path))]
          (match served ((err e) (err e)) ((ok _) (if (ok? removed) (ok 0) (err "socket path not removed"))))))))
