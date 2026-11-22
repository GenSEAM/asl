(module asl-store/purity
  :x [stripText impureHits]
  :i [])

; (:m :ref VS-CORE :do "the host boundary of the pure vault packages: a call to one of these names reads the clock, the environment, files, processes or sockets, which a pure package must receive as arguments instead")
fn names -> (List String)
  (list "(fileRead" "(fileWrite" "(fileExists" "(fileStat" "(fileAppend" "(fileLock" "(fileFsync" "(dirList" "(dirCreate" "(pathRemove" "(pathRename" "(procSelf" "(procSpawn" "(procRun" "(processRun" "(envGet" "(envList" "(fdRead" "(fdClose" "(netConnect" "(socket" "(sleepMs" "(nowNs" "(monotonicNs" "(realPath" "(execv" "(sysCall")

fn stripLoop bs: Bytes i: Int64 n: Int64 inStr: Bool inCmt: Bool acc: (List String) s: String -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (let [(b (bytesGet bs i))]
      (cond
        (inCmt (if (= b 10) (stripLoop bs (+ i 1) n inStr false (cons "\n" acc) s) (stripLoop bs (+ i 1) n inStr true acc s)))
        (inStr (cond
                 ((= b 92) (stripLoop bs (+ i 2) n true false acc s))
                 ((= b 34) (stripLoop bs (+ i 1) n false false (cons "\"" acc) s))
                 (else (stripLoop bs (+ i 1) n true false acc s))))
        ((= b 34) (stripLoop bs (+ i 1) n true false (cons "\"" acc) s))
        ((= b 59) (stripLoop bs (+ i 1) n false true acc s))
        (else (stripLoop bs (+ i 1) n false false (cons (optionOr (stringSlice s i (+ i 1)) "") acc) s)))))

; (:m :ref VS-CORE :do "source text with string literals emptied and ; comments removed, so a banned name inside a message or a comment is not a call")
fn stripText s: String -> String
  (stripLoop (stringToBytes s) 0 (stringLength s) false false (list) s)

fn impureHits text: String -> (List String)
  (let [(code (stripText text))]
    (filter (fn [(nm String)] -> Bool (stringContains? code nm)) (names)))
