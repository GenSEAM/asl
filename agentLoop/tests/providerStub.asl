(module asl/agentLoop/tests/providerStub
  :x [main]
  :i [])

fn quoted s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\r" "\\r") "\t" "\\t") "\"")

fn ! readAll fd: Int64 acc: (List String) -> (Result String String)
  (mt (fdRead fd 65536)
    ((ok chunk) (if (stringEmpty? chunk) (ok (stringJoin (listReverse acc) "")) (readAll fd (cons chunk acc))))
    ((err e) (err (str "stdin: " e))))

fn ! writeAll fd: Int64 s: String -> (Result Int64 String)
  (if (stringEmpty? s)
    (ok 0)
    (mt (fdWrite fd s)
      ((ok n) (writeAll fd (optionOr (stringSlice s n (stringLength s)) "")))
      ((err e) (err (str "stdout: " e)))))

fn afterFlag args: (List String) flag: String -> (Option String)
  (mt (listHead args)
    ((some a) (if (= a flag) (listHead (listDrop args 1)) (afterFlag (listDrop args 1) flag)))
    (none none))

fn ! optFile path: String -> String
  (resultOr (fileReadString path) "")

fn ! record dir: String name: String argv: (List String) input: String -> (Result Int64 String)
  (let [(lines (fn [xs] (stringJoin (map (fn [x] (str (quoted x) "\n")) xs) "")))
        (w1 (fileWrite (str dir "/name") name))
        (w2 (fileWrite (str dir "/argv") (lines (cons name argv))))
        (w3 (fileWrite (str dir "/stdin") input))
        (w4 (fileWrite (str dir "/env") (lines (envList))))
        (w5 (fileWrite (str dir "/cwd") (resultOr (realPath ".") "")))]
    (if (and (ok? w1) (and (ok? w2) (and (ok? w3) (and (ok? w4) (ok? w5)))))
      (ok 0)
      (err (str "cannot record under " dir))))

fn ! reply dir: String argv: (List String) -> (Result Int64 String)
  (let [(lastBody (fileReadString (str dir "/reply.last")))
        (wroteLast (mt lastBody
                     ((ok body) (mt (afterFlag argv "-o") ((some p) (fileWrite p body)) (none (ok ()))))
                     ((err _) (ok ()))))
        (pause (optionOr (stringToInt64 (stringTrim (optFile (str dir "/reply.sleepMs")))) 0))
        (slept (if (> pause 0) (sleepMs pause) ()))
        (code (optionOr (stringToInt64 (stringTrim (optFile (str dir "/reply.exit")))) 0))]
    (mt wroteLast
      ((err e) (err (str "reply.last: " e)))
      ((ok _) (mt (writeAll 1 (optFile (str dir "/reply.out")))
                ((err e) (err e))
                ((ok _) (ok code))))))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (envGet "STUB_DIR")
    (none (err "providerStub: STUB_DIR is not set"))
    ((some dir)
      (mt (listHead args)
        (none (err "providerStub: usage NAME ARGS..."))
        ((some name)
          (let [(argv (listDrop args 1))]
            (mt (readAll 0 (list))
              ((err e) (err e))
              ((ok input)
                (mt (record dir name argv input)
                  ((err e) (err e))
                  ((ok _) (reply dir argv))))))))))
