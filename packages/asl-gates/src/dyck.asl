(module asl-gates/dyck
  :x [check checkString checkFile! esc lineCol receipt reportFile! main mainWith]
  :i [])

fn esc text: String -> String
  (stringReplace (stringReplace text "\\" "\\\\") "\"" "\\\"")

fn delimToStr c: Int64 -> String
  (cond
    ((= c 40) "(")
    ((= c 41) ")")
    ((= c 91) "[")
    ((= c 93) "]")
    ((= c 123) "{")
    ((= c 125) "}")
    (else "?"))

fn checkLoop data: Bytes n: Int64 i: Int64 inStr: Bool inComment: Bool strStart: Int64 comments: Bool stack: (List (Pair Int64 Int64)) -> (Option (Pair Int64 String))
  (if (>= i n)
    (if inStr
      (some (pair strStart "unterminated string"))
      (if (not (listEmpty? stack))
        (match (listHead stack)
          ((some p) (some (pair (pairSecond p) (str "unclosed " (delimToStr (pairFirst p))))))
          ((none) (none)))
        (none)))
    (let [(c (bytesGet data i))]
      (cond
        (inComment
          (if (= c 10)
            (checkLoop data n (+ i 1) false false strStart comments stack)
            (checkLoop data n (+ i 1) false true strStart comments stack)))
        (inStr
          (cond
            ((= c 92)
              (checkLoop data n (+ i 2) true false strStart comments stack))
            ((= c 34)
              (checkLoop data n (+ i 1) false false strStart comments stack))
            (else
              (checkLoop data n (+ i 1) true false strStart comments stack))))
        ((= c 34)
          (checkLoop data n (+ i 1) true false i comments stack))
        ((and (= c 59) comments)
          (checkLoop data n (+ i 1) false true strStart comments stack))
        ((or (= c 40) (or (= c 91) (= c 123)))
          (let [(newStack (cons (pair c i) stack))]
            (checkLoop data n (+ i 1) false false strStart comments newStack)))
        ((or (= c 41) (or (= c 93) (= c 125)))
          (let [(want (cond ((= c 41) 40) ((= c 93) 91) (else 123)))]
            (if (listEmpty? stack)
              (some (pair i (str "unexpected " (delimToStr c))))
              (match (listHead stack)
                ((some p)
                  (if (!= (pairFirst p) want)
                    (some (pair i (str (delimToStr c) " closes " (delimToStr (pairFirst p)) " opened at byte " (stringFromInt64 (pairSecond p)))))
                    (checkLoop data n (+ i 1) false false strStart comments (optionOr (listTail stack) (list)))))
                ((none) (some (pair i (str "unexpected " (delimToStr c)))))))))
        (else
          (checkLoop data n (+ i 1) false false strStart comments stack)))))

fn check data: Bytes comments: Bool -> (Option (Pair Int64 String))
  (checkLoop data (bytesLength data) 0 false false 0 comments (list))

fn lineEnd data: Bytes n: Int64 i: Int64 -> Int64
  (cond ((>= i n) n) ((= (bytesGet data i) 10) (+ i 1)) (else (lineEnd data n (+ i 1))))

; (:m :ref SHEBANG :do "an ASL file's first line starting with #! is skipped as the reader skips it, so a shebang naming flags with brackets does not unbalance check")
fn checkSource data: Bytes -> (Option (Pair Int64 String))
  (let [(n (bytesLength data))
        (start (if (and (>= n 2) (and (= (bytesGet data 0) 35) (= (bytesGet data 1) 33))) (lineEnd data n 0) 0))]
    (checkLoop data n start false false 0 false (list)))

fn checkString text: String comments: Bool -> (Option (Pair Int64 String))
  (check (stringToBytes text) comments)

fn extractStrerror path: String err: String -> String
  (let [(firstColon (optionOr (stringIndexOf err ": ") -1))]
    (let [(rest (optionOr (stringSlice err (+ firstColon 2) (stringLength err)) ""))]
      (let [(pathLen (stringLength path))]
        (optionOr (stringSlice rest (+ pathLen 2) (stringLength rest)) rest))))

fn checkFile! path: String -> (Result (Option (Pair Int64 String)) String)
  (match (fileStat path)
    ((ok st)
      (if st.isDir
        (err "Is a directory")
        (let [(r (fileReadBytes path))]
          (match r
            ((ok data) (ok (if (stringEndsWith? path ".asl") (checkSource data) (check data true))))
            ((err e) (err (extractStrerror path e)))))))
    ((err e)
      (err (extractStrerror path e))))

fn maxRc a: Int64 b: Int64 -> Int64
  (if (> a b) a b)

; (:m :ref PAREN-CHECK-DIAG :do "1-based line and column of a byte offset, so a receipt names a place an editor and a model can find")
fn lineColLoop data: Bytes off: Int64 i: Int64 line: Int64 start: Int64 -> (Pair Int64 Int64)
  (cond
    ((>= i off) (pair line (+ (- off start) 1)))
    ((= (bytesGet data i) 10) (lineColLoop data off (+ i 1) (+ line 1) (+ i 1)))
    (else (lineColLoop data off (+ i 1) line start)))

fn lineCol data: Bytes off: Int64 -> (Pair Int64 Int64)
  (lineColLoop data (min off (bytesLength data)) 0 1 0)

fn at data: Bytes off: Int64 -> String
  (let [(lc (lineCol data off))]
    (str (stringFromInt64 (pairFirst lc)) ":" (stringFromInt64 (pairSecond lc))))

; (:m :ref PAREN-CHECK-DIAG :do "the check message names the opener as line:col; check itself keeps byte offsets for its callers")
fn evText data: Bytes msg: String -> String
  (match (stringIndexOf msg " opened at byte ")
    ((none) msg)
    ((some i)
      (match (stringToInt64 (optionOr (stringSlice msg (+ i 16) (stringLength msg)) ""))
        ((some off) (str (optionOr (stringSlice msg 0 i) msg) " opened at " (at data off)))
        ((none) msg))))

fn receipt p: String data: Bytes unb: (Pair Int64 String) extra: String -> String
  (let [(lc (lineCol data (pairFirst unb)))]
    (str "(:unbalanced :file \"" (esc p) "\" :line " (stringFromInt64 (pairFirst lc)) " :col " (stringFromInt64 (pairSecond lc))
         " :ev \"" (esc (evText data (pairSecond unb))) "\"" extra ")"))

; (:m :ref PAREN-CHECK-DIAG :do "one file's balance verdict as (exit, receipt line); hint adds fields for an unbalanced file, so a caller with a repair engine can name the fix without this module depending on it")
fn reportFile! p: String hint: (fn [String] -> String) -> (Pair Int64 String)
  (match (checkFile! p)
    ((err errEv) (pair 2 (str "(:unreadable :file \"" (esc p) "\" :ev \"" (esc errEv) "\")")))
    ((ok res)
      (match res
        ((none) (pair 0 ""))
        ((some unb) (pair 1 (receipt p (resultOr (fileReadBytes p) (stringToBytes "")) unb (hint p)))))))

fn sayIf! line: String -> Bool
  (if (stringEmpty? line) false (do (println line) true))

fn processPaths! paths: (List String) rc: Int64 hint: (fn [String] -> String) -> Int64
  (match (listHead paths)
    ((none) rc)
    ((some p)
      (let [(r (reportFile! p hint))
            (_ (sayIf! (pairSecond r)))]
        (processPaths! (optionOr (listTail paths) (list)) (maxRc rc (pairFirst r)) hint))))

fn noHint p: String -> String
  ""

fn ! mainWith paths: (List String) hint: (fn [String] -> String) -> (Result Int64 String)
  (if (listEmpty? paths)
    (do
      (eprintln "usage: dyck.py FILE...")
      (ok 64))
    (ok (processPaths! paths 0 hint)))

fn ! main paths: (List String) -> (Result Int64 String)
  (mainWith paths noHint)
