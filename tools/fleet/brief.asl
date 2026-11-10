(module asl-tools/fleet/brief
  :x [Brief parseBrief validate! pathTokens taskTokens rowOf! promptOf! buildForm main]
  :i [(asl-tools/fleet/run :a fr) (asl-parser/reader :a rd)])

; (:m :ref DS-ASSIST-ROLES :do "the BRIEFER: a plan row plus a worktree root become a ready (:agent ...) form; a read-only Leon run (owns = one scratch file under .asl/mem/work/brief) writes a (:brief :task :owns :gates) form from prefetched outlines and query hits, a deterministic validator then checks every named path, file#symbol, owns entry, gate command and the parse, one retry feeds the errors back, and a second failure prints a receipt listing them; bin/asl run asl/tools/fleet/brief.asl ROW-OR-ID ROOT [--model M] [--budget N] [--timeout S] [--plan FILE] [--out FILE]")

(schema Brief
  (:f task String)
  (:f owns (List String))
  (:f gates (List String))
  (:f rawTask String)
  (:f errors (List String)))

fn unq a: String -> String
  (let [(n (stringLength a))]
    (if (and (>= n 2) (and (stringStartsWith? a "\"") (stringEndsWith? a "\"")))
      (stringReplace (stringReplace (optionOr (stringSlice a 1 (- n 1)) "") "\\\"" "\"") "\\\\" "\\")
      a))

fn kvAt xs: (List rd/SExpr) key: String -> (Option rd/SExpr)
  (match (listHead xs)
    ((none) none)
    ((some k)
      (let [(rest (optionOr (listTail xs) (list)))]
        (if (= (rd/sexprHead k) key) (listHead rest) (kvAt (optionOr (listTail rest) (list)) key)))))

; (:m :do "delimiters balanced outside string literals; the first defect is named")
fn balanceError text: String -> String
  (let [(cs (stringChars text))]
    (balScan cs 0 false false))

fn balScan cs: (List String) depth: Int64 inStr: Bool esc: Bool -> String
  (match (listHead cs)
    ((none) (cond (inStr "unterminated string") ((> depth 0) "unclosed (") (else "")))
    ((some c)
      (let [(rest (optionOr (listTail cs) (list)))]
        (cond
          (inStr (if esc (balScan rest depth true false)
                   (cond ((= c "\\") (balScan rest depth true true)) ((= c "\"") (balScan rest depth false false)) (else (balScan rest depth true false)))))
          ((= c "\"") (balScan rest depth true false))
          ((= c "(") (balScan rest (+ depth 1) false false))
          ((= c ")") (if (<= depth 0) "unbalanced )" (balScan rest (- depth 1) false false)))
          (else (balScan rest depth false false))))))

fn strList s: rd/SExpr -> (List String)
  (map (fn [(x rd/SExpr)] -> String (unq (rd/sexprHead x))) (rd/sexprToList s))

; (:m :do "text of a brief form to a Brief; a defect lands in errors and the other fields stay empty")
fn parseBrief text: String -> Brief
  (let [(bad (balanceError text))]
    (if (not (stringEmpty? bad))
      (Brief :task "" :owns (list) :gates (list) :rawTask "" :errors (list (str "form does not parse: " bad)))
      (let [(s (rd/parseSexpr text))
            (xs (optionOr (listTail (rd/sexprToList s)) (list)))
            (t (kvAt xs ":task"))
            (o (kvAt xs ":owns"))
            (g (kvAt xs ":gates"))
            (raw (match t ((some v) (rd/sexprHead v)) ((none) "")))
            (head (optionOr (listHead (rd/sexprToList s)) s))]
        (Brief :task (unq raw)
               :owns (match o ((some v) (strList v)) ((none) (list)))
               :gates (match g ((some v) (strList v)) ((none) (list)))
               :rawTask raw
               :errors (listAppend
                         (if (= (rd/sexprHead head) ":brief") (list) (list "form head is not (:brief ...)"))
                         (listAppend (if (stringEmpty? (stringTrim (unq raw))) (list "missing :task") (list))
                           (listAppend (match o ((some _) (list)) ((none) (list "missing :owns")))
                                       (match g ((some _) (list)) ((none) (list "missing :gates"))))))))))

fn trimTok t: String -> String
  (if (and (> (stringLength t) 0) (listContains? (list "." ":" "'" "`" "!" "?") (optionOr (stringSlice t (- (stringLength t) 1) (stringLength t)) "")))
    (trimTok (optionOr (stringSlice t 0 (- (stringLength t) 1)) ""))
    t)

fn splitWords text: String -> (List String)
  (let [(flat (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace text "(" " ") ")" " ") "\"" " ") "," " ") ";" " ") "\n" " "))]
    (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (map trimTok (stringSplit flat " "))))

fn pathLike? w: String -> Bool
  (and (stringContains? w "/")
       (and (not (stringStartsWith? w "/")) (and (not (stringStartsWith? w "~"))
            (and (not (stringContains? w "*")) (and (not (stringContains? w "<")) (and (not (stringContains? w "$")) (and (not (stringContains? w "..."))
                 (listAny? (fn [(e String)] -> Bool (stringEndsWith? (optionOr (listHead (stringSplit w "#")) w) e)) (list ".asl" ".asn" ".md")))))))))

; (:m :do "the path-like words of a text, each split at # into a file and an optional symbol; an entry is file or file#symbol")
fn pathTokens text: String -> (List String)
  (filter pathLike? (splitWords text))

fn taskTokens text: String -> (List String)
  (pathTokens text)

fn ! resolves! root: String file: String sym: String -> Bool
  (let [(form (str "(:read :file " file " :symbol " sym ")"))
        (d (fr/runOneLimited (fr/job (list (str root "/bin/asl") form) root (fr/childEnv (list))) (fr/limits 120 16)))]
    (and (= d.exit 0) (not (stringContains? (optionOr (stringSlice d.out 0 40) "") ":status :rejected"))))

fn ! dirOf p: String -> String
  (let [(parts (stringSplit p "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn ! newTestPath? root: String p: String -> Bool
  (and (stringContains? p "/tests/") (and (stringEndsWith? p ".asl") (fileExists? (str root "/" (dirOf p)))))

fn ! pathError! root: String owns: (List String) tok: String -> (List String)
  (let [(parts (stringSplit tok "#"))
        (file (optionOr (listHead parts) tok))
        (sym (if (> (listLength parts) 1) (optionOr (listGet parts 1) "") ""))
        (present (fileExists? (str root "/" file)))
        (planned (or (listContains? owns file) (newTestPath? root file)))]
    (cond
      ((and (not present) (not planned)) (list (str "path not found: " file)))
      ((and (not (stringEmpty? sym)) (not present)) (list (str "symbol of a new file cannot be read: " tok)))
      ((and (not (stringEmpty? sym)) (not (resolves! root file sym))) (list (str "symbol not found: " file "#" sym)))
      (else (list))))

fn ! gateError! root: String g: String -> (List String)
  (let [(pre "env -u ASL_ROOT -u ASL_PRELUDE ")
        (body (if (stringStartsWith? g pre) (optionOr (stringSlice g (stringLength pre) (stringLength g)) "") g))
        (tp "./bin/asl test ")]
    (if (not (stringStartsWith? body tp))
      (list (str "gate is not ./bin/asl test PATH: " g))
      (let [(p (stringTrim (optionOr (stringSlice body (stringLength tp) (stringLength body)) "")))]
        (cond ((stringContains? p " ") (list (str "gate has more than one path: " g)))
              ((or (fileExists? (str root "/" p)) (newTestPath? root p)) (list))
              (else (list (str "gate test path not found: " p)))))))

fn ! ownsError! root: String o: String -> (List String)
  (cond ((or (stringStartsWith? o "/") (stringContains? o "..")) (list (str "owns entry escapes the root: " o)))
        ((or (fileExists? (str root "/" o)) (fileExists? (str root "/" (dirOf o)))) (list))
        (else (list (str "owns entry has no existing directory: " o))))

fn flat xss: (List (List String)) -> (List String)
  (match (listHead xss) ((none) (list)) ((some x) (listAppend x (flat (optionOr (listTail xss) (list))))))

; (:m :ref DS-ASSIST-ROLES :do "deterministic validation of a brief text against a worktree root: parse, non-empty owns and gates, every named file exists (or is a new test under tests/ or an owned new file), every file#symbol resolves through (:read :symbol), each gate is an ./bin/asl test command on an existing or new test; returns the error list, empty when valid")
fn ! validate! root: String text: String -> (List String)
  (let [(b (parseBrief text))]
    (if (not (listEmpty? b.errors))
      b.errors
      (listAppend
        (if (listEmpty? b.owns) (list "empty :owns") (list))
        (listAppend
          (if (listEmpty? b.gates) (list "empty :gates") (list))
          (listAppend (flat (map (fn [(o String)] -> (List String) (ownsError! root o)) b.owns))
            (listAppend (flat (map (fn [(g String)] -> (List String) (gateError! root g)) b.gates))
                        (flat (map (fn [(t String)] -> (List String) (pathError! root b.owns t)) (listConcatDistinct (taskTokens b.task))))))))))

fn listConcatDistinct xs: (List String) -> (List String)
  (match (listHead xs)
    ((none) (list))
    ((some x) (let [(rest (optionOr (listTail xs) (list)))]
                (if (listContains? rest x) (listConcatDistinct rest) (cons x (listConcatDistinct rest))))))

fn escQ s: String -> String
  (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" " ")

fn rowIdOf row: String -> String
  (let [(w (splitWords row))]
    (match (listIndexOf w ":id") ((some i) (optionOr (listGet w (+ i 1)) "") ) ((none) "")))

; (:m :do "a row from a file holding it (the first (:u line) or from the id in a plan file; an empty plan path falls back to the main workspace beside the worktree's git common dir")
fn ! rowOf! arg: String root: String plan: String -> String
  (if (fileExists? arg)
    (optionOr (listFind (fn [(l String)] -> Bool (stringStartsWith? l "(:u ")) (stringLines (resultOr (fileReadString arg) ""))) "")
    (let [(rel "/.asl/mem/work/SH/plan.asn")
          (common (stringTrim (fr/runOneLimited (fr/job (list "git" "-C" root "rev-parse" "--git-common-dir") root (fr/childEnv (list))) (fr/limits 30 4)).out))
          (mainRoot (if (stringEndsWith? common "/.git") (optionOr (stringSlice common 0 (- (stringLength common) 5)) "") ""))
          (path (cond ((not (stringEmpty? plan)) plan) ((fileExists? (str root rel)) (str root rel)) (else (str mainRoot rel))))
          (key (str "(:u :id " arg " "))]
      (optionOr (listFind (fn [(l String)] -> Bool (stringStartsWith? l key)) (stringLines (resultOr (fileReadString path) ""))) "")))

fn ! nowMs -> Int64
  (/ (nowNs) 1000000)

fn clip s: String n: Int64 -> String
  (if (> (stringLength s) n) (str (optionOr (stringSlice s 0 n) "") " ...") s)

fn ! outlineOf! root: String file: String -> String
  (let [(d (fr/runOneLimited (fr/job (list (str root "/bin/asl") (str "(:intel :op outline :file " file ")")) root (fr/childEnv (list))) (fr/limits 120 16)))]
    (clip d.out 2500))

fn ! queryOf! root: String word: String -> String
  (let [(d (fr/runOneLimited (fr/job (list (str root "/bin/asl") (str "(:query :text " word " :limit 6)")) root (fr/childEnv (list))) (fr/limits 120 16)))]
    (clip d.out 1200))

fn identLike? w: String -> Bool
  (and (>= (stringLength w) 6)
       (and (not (stringContains? w "/")) (and (not (stringContains? w ":")) (and (not (stringContains? w "-"))
            (and (listAny? (fn [(c String)] -> Bool (and (>= (charCode c) 65) (<= (charCode c) 90))) (stringChars w))
                 (not (stringStartsWith? w "(")))))))

; (:m :do "prefetched context: an outline of each existing file the row names and at most three query hits for its identifier-like words")
fn ! contextOf! root: String row: String -> String
  (let [(files (listConcatDistinct (map (fn [(t String)] -> String (optionOr (listHead (stringSplit t "#")) t)) (pathTokens row))))
        (have (filter (fn [(f String)] -> Bool (fileExists? (str root "/" f))) (listTake files 4)))
        (words (listTake (listConcatDistinct (filter identLike? (splitWords row))) 3))]
    (str (stringJoin (map (fn [(f String)] -> String (str "OUTLINE " f ": " (outlineOf! root f))) have) " ")
         " "
         (stringJoin (map (fn [(w String)] -> String (str "QUERY " w ": " (queryOf! root w))) words) " ")))

fn ! promptOf! id: String row: String ctx: String scratch: String errors: (List String) -> String
  (stringReplace (str "Unit BRIEFER-" id ". You are a read-only briefer; change no code. Turn the plan row below into a writer brief. Turn 1, one batch: read the files and symbols the row names with (:read :file F :symbol S) and (:query :text T); turn 2: find the closest existing test to copy its shape from. Then write exactly one file " scratch " with (:write :file " scratch " :content C) where C is one form (:brief :task T :owns (P ...) :gates (G ...)). T is ONE string with no double quotes and no newlines, shaped like: Unit ID. Problem in one sentence. Change: file#fn what changes, with the exact new behaviour and record fields. Turn 1 reads, one batch: file#symbol list. New test PATH in a fresh temp dir under TMPDIR: each case with its expected result. Prove red before: git diff > file, git apply -R, rerun, git apply (git stash forbidden). Finish with a commit: one ASN line (:c :a AREA :do WHAT :g TESTNAME :ev ID), named paths only (git commit -- paths). Rules: every path in T must exist or be a new test under a tests/ directory; every file#symbol in T must resolve with (:read); write file#symbol with a real function name; P entries are the source files to edit plus the new test; each G is exactly env -u ASL_ROOT -u ASL_PRELUDE ./bin/asl test PATH for the new test or an existing test of a touched file. Plan row: " row " Prefetched context: " ctx
                   (if (listEmpty? errors) "" (str " Your previous brief was rejected, fix exactly these and write the file again: " (stringJoin errors " | "))))
                 "\n" " ")

fn ! agentArgv! root: String model: String budget: Int64 timeout: Int64 scratchRel: String id: String prompt: String -> (List String)
  (list (str root "/bin/asl")
        (str "(:agent :task \"" (escQ prompt) "\" :root \"" root "\" :owns (\"" scratchRel "\") :model " model " :intent any :budget " (stringFromInt64 budget) " :timeout " (stringFromInt64 timeout) " :unit \"BRIEFER-" id "\")"))

fn ! buildForm root: String id: String b: Brief model: String budget: Int64 timeout: Int64 unit: String -> String
  (str "(:agent :task " b.rawTask " :root \"" root "\" :owns (" (stringJoin (map (fn [(o String)] -> String (str "\"" o "\"")) b.owns) " ") ") :gates ("
       (stringJoin (map (fn [(g String)] -> String (str "\"" g "\"")) b.gates) " ") ") :model " model " :intent any :budget " (stringFromInt64 budget)
       " :timeout " (stringFromInt64 timeout) " :wallBudget " (stringFromInt64 timeout) " :unit \"" unit "\")")

fn optArg args: (List String) key: String dflt: String -> String
  (match (listIndexOf args key) ((some i) (optionOr (listGet args (+ i 1)) dflt)) ((none) dflt))

fn ! attempt! root: String id: String row: String ctx: String model: String budget: Int64 timeout: Int64 scratch: String errors: (List String) -> (List String)
  (let [(rel (optionOr (stringSlice scratch (+ (stringLength root) 1) (stringLength scratch)) scratch))
        (_ (pathRemove scratch))
        (d (fr/runOneLimited (fr/job (agentArgv! root model budget timeout rel id (promptOf! id row ctx rel errors)) root (fr/childEnv (list))) (fr/limits (+ timeout 60) 64)))]
    (match (fileReadString scratch)
      ((err _) (list (str "the briefer wrote no brief file; agent exit " (stringFromInt64 d.exit) " " (clip (stringReplace d.out "\n" " ") 300))))
      ((ok text) (validate! root text))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(arg (optionOr (listHead args) ""))
        (root (resultOr (realPath (optionOr (listGet args 1) ".")) "."))
        (model (optArg args "--model" "synDs41FlashT1H"))
        (budget (optionOr (stringToInt64 (optArg args "--budget" "24")) 24))
        (timeout (optionOr (stringToInt64 (optArg args "--timeout" "900")) 900))
        (row (rowOf! arg root (optArg args "--plan" "")))
        (id (let [(i (rowIdOf row))] (if (stringEmpty? i) arg i)))
        (scratch (str root "/.asl/mem/work/brief/brief-" id ".asn"))
        (out (optArg args "--out" (str root "/.asl/mem/work/brief/brief-" id ".agent.asn")))]
    (if (or (stringEmpty? arg) (stringEmpty? row))
      (do (eprintln "usage: bin/asl run asl/tools/fleet/brief.asl ROW-FILE-OR-ID ROOT [--model M] [--budget N] [--timeout S] [--plan FILE] [--out FILE]; the row was not found") (ok 2))
      (let [(_ (dirCreate (str root "/.asl/mem/work/brief")))
            (t0 (nowMs))
            (ctx (contextOf! root row))
            (e1 (attempt! root id row ctx model budget timeout scratch (list)))
            (e2 (if (listEmpty? e1) (list) (attempt! root id row ctx model budget timeout scratch e1)))]
        (if (listEmpty? e2)
          (let [(b (parseBrief (resultOr (fileReadString scratch) "")))
                (form (buildForm root id b model budget timeout id))
                (_ (fileWrite out (str form "\n")))]
            (do (println (str "(:brief :status ok :unit \"" id "\" :file \"" out "\" :attempts " (if (listEmpty? e1) "1" "2") " :ms " (stringFromInt64 (- (nowMs) t0)) " :firstErrors (" (stringJoin (map (fn [(e String)] -> String (str "\"" (escQ e) "\"")) e1) " ") ") :errors ())")) (ok 0)))
          (do (println (str "(:brief :status failed :unit \"" id "\" :attempts 2 :ms " (stringFromInt64 (- (nowMs) t0)) " :errors (" (stringJoin (map (fn [(e String)] -> String (str "\"" (escQ e) "\"")) e2) " ") "))")) (ok 1))))))

