(module asl-gates/dyck
  :x [check checkString checkFile! esc main]
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
        (mt (listHead stack)
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
              (mt (listHead stack)
                ((some p)
                  (if (!= (pairFirst p) want)
                    (some (pair i (str (delimToStr c) " closes " (delimToStr (pairFirst p)) " opened at byte " (stringFromInt64 (pairSecond p)))))
                    (checkLoop data n (+ i 1) false false strStart comments (optionOr (listTail stack) (list)))))
                ((none) (some (pair i (str "unexpected " (delimToStr c)))))))))
        (else
          (checkLoop data n (+ i 1) false false strStart comments stack)))))

fn check data: Bytes comments: Bool -> (Option (Pair Int64 String))
  (checkLoop data (bytesLength data) 0 false false 0 comments (list))

fn checkString text: String comments: Bool -> (Option (Pair Int64 String))
  (check (stringToBytes text) comments)

fn extractStrerror path: String err: String -> String
  (let [(firstColon (optionOr (stringIndexOf err ": ") -1))]
    (let [(rest (optionOr (stringSlice err (+ firstColon 2) (stringLength err)) ""))]
      (let [(pathLen (stringLength path))]
        (optionOr (stringSlice rest (+ pathLen 2) (stringLength rest)) rest))))

fn checkFile! path: String -> (Result (Option (Pair Int64 String)) String)
  (mt (fileStat path)
    ((ok st)
      (if st.isDir
        (err "Is a directory")
        (let [(r (fileReadBytes path))]
          (mt r
            ((ok data) (ok (check data (not (stringEndsWith? path ".asl")))))
            ((err e) (err (extractStrerror path e)))))))
    ((err e)
      (err (extractStrerror path e))))

fn maxRc a: Int64 b: Int64 -> Int64
  (if (> a b) a b)

fn processPaths! paths: (List String) rc: Int64 -> Int64
  (if (listEmpty? paths)
    rc
    (let [(p (optionOr (listHead paths) ""))
          (tail (optionOr (listTail paths) (list)))
          (r (checkFile! p))]
      (mt r
        ((err errEv)
          (let [(_ (println (str "(:unreadable :file \"" (esc p) "\" :ev \"" (esc errEv) "\")")))]
            (processPaths! tail 2)))
        ((ok res)
          (mt res
            ((none) (processPaths! tail rc))
            ((some unb)
              (let [(byteOff (pairFirst unb))
                    (msg (pairSecond unb))
                    (_ (println (str "(:unbalanced :file \"" (esc p) "\" :byte " (stringFromInt64 byteOff) " :ev \"" (esc msg) "\")")))]
                (processPaths! tail (maxRc rc 1)))))))))
fn ! main paths: (List String) -> (Result Int64 String)
  (if (listEmpty? paths)
    (do
      (eprintln "usage: dyck.py FILE...")
      (ok 64))
    (let [(rc (processPaths! paths 0))]
      (ok rc)))
