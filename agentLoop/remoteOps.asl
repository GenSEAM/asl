(module asl/agentLoop/remoteOps
  :x [remoteOpNames remoteUnit remoteOp! splitOn]
  :i [(asl/agentLoop/core :a c)
      (tools/remote/form :a fm)
      (tools/remote/transport :a tr)
      (tools/remote/vps :a vp)])

; (:m :ref LEON-REMOTE-TOOLS :do "a step carrying :remote UNIT runs read, write, edit, check, test or run in the VPS worktree ~/wt/UNIT through tools/remote/vps (relay when the config says via relay and it answers, ssh otherwise); the file stays on the VPS, edit reads it, replaces exactly one match locally and writes it back as stdin of one remote cat, and every answer is a flat list of string fields the caller turns into a receipt")
fn remoteOpNames -> (List String)
  (list "read" "write" "edit" "check" "test" "run")

fn opStr op: (List (Pair String c/KvVal)) key: String fallback: String -> String
  (match (listFind (fn [p] (= (pairFirst p) key)) op)
    ((some p) (match (pairSecond p) ((c/kvStr s) s) ((c/kvInt s) s) (_ fallback)))
    ((none) fallback))

fn remoteUnit op: (List (Pair String c/KvVal)) -> String
  (stringTrim (opStr op "remote" ""))

fn f k: String v: String -> (Pair String String)
  (pair k v)

fn failed id: String opName: String unit: String code: String msg: String -> (List (Pair String String))
  (list (f "id" id) (f "op" opName) (f "remote" unit) (f "status" "error") (f "error" code) (f "message" msg))

fn cfgPath op: (List (Pair String c/KvVal)) -> String
  (let [given (opStr op "remoteCfg" "")]
    (if (stringEmpty? given) (str (resultOr (getHomeDir) "") "/.asl/remote.asn") given))

fn splitOn s: String sep: String -> (List String)
  (stringSplit s sep)

fn cap s: String n: Int64 -> String
  (if (> (stringLength s) n) (str (optionOr (stringSlice s 0 n) "") "\n...truncated") s)

fn unreachable? e: vp/Exec -> Bool
  (or (< e.exit 0) (= e.exit 255))

fn noDir? e: vp/Exec -> Bool
  (and (= e.exit 3) (stringContains? e.out "noDir"))

fn ! catRemote! cfg: vp/VpsCfg unit: String file: String timeoutS: Int64 -> vp/Exec
  (vp/exec! cfg (vp/inDir (vp/wtPath cfg unit) (list "cat" "--" file)) timeoutS)

fn writeScript -> String
  "mkdir -p \"$(dirname -- \"$1\")\" && cat > \"$1\""

fn ! putRemote! cfg: vp/VpsCfg unit: String file: String content: String timeoutS: Int64 -> vp/Exec
  (match (tr/scratchFile! "leonput" content)
    ((err e) (vp/Exec :exit -1 :out "" :err e))
    ((ok path)
      (let [e (vp/execTo! cfg (vp/inDir (vp/wtPath cfg unit) (list "sh" "-c" (writeScript) "sh" file)) timeoutS path "")
            _ (tr/scratchDrop! path)]
        e)))

fn ! readRec! cfg: vp/VpsCfg id: String unit: String file: String capN: Int64 timeoutS: Int64 -> (List (Pair String String))
  (let [e (catRemote! cfg unit file timeoutS)]
    (cond
      ((unreachable? e) (failed id "read" unit "ERR_REMOTE_UNREACHABLE" e.err))
      ((noDir? e) (failed id "read" unit "ERR_REMOTE_NO_WORKTREE" (str "no worktree " unit)))
      ((!= e.exit 0) (failed id "read" unit "ERR_REMOTE_READ" (str "cannot read " file ": " (cap e.err 400))))
      (else (list (f "id" id) (f "op" "read") (f "remote" unit) (f "status" "ok") (f "file" file) (f "exit" "0") (f "content" (cap e.out capN))))))

fn ! writeRec! cfg: vp/VpsCfg id: String unit: String opName: String file: String content: String timeoutS: Int64 -> (List (Pair String String))
  (let [e (putRemote! cfg unit file content timeoutS)]
    (cond
      ((unreachable? e) (failed id opName unit "ERR_REMOTE_UNREACHABLE" e.err))
      ((noDir? e) (failed id opName unit "ERR_REMOTE_NO_WORKTREE" (str "no worktree " unit)))
      ((!= e.exit 0) (failed id opName unit "ERR_REMOTE_WRITE" (str "cannot write " file ": " (cap e.err 400))))
      (else (list (f "id" id) (f "op" opName) (f "remote" unit) (f "status" "ok") (f "file" file) (f "exit" "0") (f "bytes" (stringFromInt64 (stringLength content)))))))

fn ! editRec! cfg: vp/VpsCfg id: String unit: String file: String old: String new: String timeoutS: Int64 -> (List (Pair String String))
  (let [e (catRemote! cfg unit file timeoutS)
        parts (splitOn e.out old)
        hits (- (listLength parts) 1)]
    (cond
      ((stringEmpty? old) (failed id "edit" unit "ERR_MISSING_ARG" "edit needs a non-empty :old"))
      ((unreachable? e) (failed id "edit" unit "ERR_REMOTE_UNREACHABLE" e.err))
      ((noDir? e) (failed id "edit" unit "ERR_REMOTE_NO_WORKTREE" (str "no worktree " unit)))
      ((!= e.exit 0) (failed id "edit" unit "ERR_REMOTE_READ" (str "cannot read " file ": " (cap e.err 400))))
      ((= hits 0) (failed id "edit" unit "ERR_EDIT_NOMATCH" (str ":old does not occur in " file)))
      ((> hits 1) (failed id "edit" unit "ERR_EDIT_AMBIGUOUS" (str ":old occurs " (stringFromInt64 hits) " times in " file "; add context")))
      (else (writeRec! cfg id unit "edit" file (stringJoin parts new) timeoutS))))

fn receiptRec id: String opName: String unit: String receipt: String -> (List (Pair String String))
  (let [bad (or (stringContains? receipt "(:err ") (not (stringContains? receipt ":failed 0")))]
    (list (f "id" id) (f "op" opName) (f "remote" unit) (f "status" (if bad "failed" "ok")) (f "exit" (if bad "1" "0")) (f "receipt" receipt)))

fn filesOf op: (List (Pair String c/KvVal)) -> (List String)
  (let [one (opStr op "file" "")]
    (if (stringEmpty? one)
      (filter (fn [w] (not (stringEmpty? w))) (stringSplit (opStr op "files" "") " "))
      (list one)))

fn ! runRec! cfg: vp/VpsCfg id: String unit: String cmd: String timeoutS: Int64 -> (List (Pair String String))
  (let [r (vp/shell! cfg unit cmd timeoutS)]
    (list (f "id" id) (f "op" "run") (f "remote" unit) (f "status" (if (stringContains? r ":exit 0") "ok" "failed")) (f "receipt" r)))

; (:m :ref LEON-REMOTE-TOOLS :do "the worktree-relative path rule of tools/remote/form refuses absolute, dotted and dashed paths before any ssh or relay round trip")
fn ! remoteOp! op: (List (Pair String c/KvVal)) opName: String id: String timeoutS: Int64 readCap: Int64 -> (List (Pair String String))
  (let [unit (remoteUnit op)
        file (opStr op "file" "")
        needsFile (listContains? (list "read" "write" "edit") opName)
        loaded (vp/loadVpsCfg! (cfgPath op))]
    (cond
      ((not (fm/safeUnit? unit)) (failed id opName unit "ERR_REMOTE_UNIT" "remote needs a unit name of letters, digits and dashes"))
      ((and needsFile (not (fm/safePath? file))) (failed id opName unit "ERR_REMOTE_PATH" "file must be a worktree-relative path without dot or dash segments"))
      (else
        (match loaded
          ((err e) (failed id opName unit "ERR_REMOTE_NO_CONFIG" e))
          ((ok cfg)
            (cond
              ((= opName "read") (readRec! cfg id unit file readCap timeoutS))
              ((= opName "write") (writeRec! cfg id unit "write" file (opStr op "content" "") timeoutS))
              ((= opName "edit") (editRec! cfg id unit file (opStr op "old" "") (opStr op "new" "") timeoutS))
              ((= opName "check") (receiptRec id opName unit (vp/check! cfg unit (filesOf op) 2 timeoutS)))
              ((= opName "test") (receiptRec id opName unit (vp/test! cfg unit (filesOf op) 2 timeoutS)))
              (else (runRec! cfg id unit (opStr op "cmd" (opStr op "argv" "")) timeoutS))))))))
