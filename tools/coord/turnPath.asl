(module asl-tools/coord/turnPath
  :x [Step Path rejectClass pathOfText pathLine stepLine summaryText reportDir main]
  :i [])

; (:m :ref TURN-PATH-EFFICIENCY :do "how a Leon session spent its turns, read from the agent loop journals (*.journal): every turn gets one letter and one cause, progress (a read that a later accepted write edits or names, an accepted write, a gate after a change) or a loss (reread scout readNoWrite inspect noOp rejected:<class> gateFirst gateSame toolErr:<code> wait doneRefused close afterGreen unknown); a session that landed a write has an ideal path, at most two turns for its used reads, because a reply may carry several steps, plus one turn per written file plus a gate turn unless the loop gated on its own, and excess is turns minus that; lines that are not one whole row are skipped and counted")

(schema Op
  (:f name String) (:f file String) (:f at String) (:f status String) (:f error String))

(schema Turn
  (:f n Int64) (:f ops (List Op)) (:f inT Int64) (:f outT Int64) (:f cached Int64)
  (:f reply String) (:f replied Bool) (:f obs String) (:f gateRows Int64) (:f gateRed Int64)
  (:f error String) (:f waitSec Int64))

(schema Scan
  (:f journal String) (:f task String) (:f alias String) (:f stop String) (:f written Bool)
  (:f baseline Bool) (:f done (List Turn)) (:f cur Turn) (:f open Bool) (:f skipped Int64))

(schema Step
  (:f turn Int64) (:f letter String) (:f cause String) (:f inT Int64) (:f outT Int64) (:f cached Int64) (:f rejectedOps Int64) (:f preview String))

(schema Path
  (:f session String) (:f unit String) (:f model String) (:f turns Int64) (:f outcome String)
  (:f inT Int64) (:f outT Int64) (:f cached Int64) (:f shape String) (:f firstWriteTurn Int64)
  (:f wrote Bool) (:f files Int64) (:f ideal Int64) (:f excess Int64) (:f skipped Int64) (:f steps (List Step)))

(schema Seen
  (:f name String) (:f file String) (:f at String) (:f arg String))

(schema Landed
  (:f at Int64) (:f files (List String)) (:f reply String))

(schema Cls
  (:f seen (List Seen)) (:f changed Bool) (:f verified Bool) (:f anyMut Bool) (:f green Bool)
  (:f autoGate Bool) (:f files (List String)) (:f firstWrite Int64) (:f steps (List Step)))

(schema Loaded
  (:f paths (List Path)) (:f unreadable Int64) (:f empty Int64) (:f skipped Int64))

(schema Tally
  (:f key String) (:f turns Int64) (:f inT Int64) (:f outT Int64))

fn n x: Int64 -> String
  (stringFromInt64 x)

fn after s: String key: String -> String
  (match (stringIndexOf s key)
    ((none) "")
    ((some i) (optionOr (stringSlice s (+ i (stringLength key)) (stringLength s)) "")))

fn upTo s: String stop: String -> String
  (match (stringIndexOf s stop)
    ((none) s)
    ((some i) (optionOr (stringSlice s 0 i) "")))

fn clip s: String k: Int64 -> String
  (if (<= (stringLength s) k) s (optionOr (stringSlice s 0 k) ""))

fn quoted line: String key: String -> String
  (upTo (after line (str key " \"")) "\"")

fn tok line: String key: String -> String
  (upTo (upTo (after line (str key " ")) " ") ")")

fn intOf s: String -> Int64
  (optionOr (stringToInt64 s) 0)

fn plain s: String -> String
  (stringTrim (stringReplace (stringReplace (stringReplace s "\\n" " ") "\\" "") "\"" "'"))

fn emptyTurn k: Int64 -> Turn
  (Turn :n k :ops (list) :inT 0 :outT 0 :cached 0 :reply "" :replied false :obs "" :gateRows 0 :gateRed 0 :error "" :waitSec 0)

fn emptyScan -> Scan
  (Scan :journal "" :task "" :alias "" :stop "" :written false :baseline false :done (list) :cur (emptyTurn 0) :open false :skipped 0)

; (:m :do "a row that names turn K belongs to turn K: when K is not the open turn the open one is closed first, so a journal that lost its :sent row to a cut still yields the turn")
fn atTurn acc: Scan k: Int64 -> Scan
  (if (and acc.open (= acc.cur.n k))
    acc
    (with acc :done (if acc.open (cons acc.cur acc.done) acc.done) :cur (emptyTurn k) :open true))

fn wholeText? l: String -> Bool
  (stringEndsWith? l "\")")

fn turnRow acc: Scan l: String head: String -> Scan
  (let [(parts (stringSplit head " "))
        (num (stringToInt64 (optionOr (listGet parts 1) "")))
        (kind (stringReplace (optionOr (listGet parts 2) "") ")" ""))]
    (match num
      ((none) (with acc :skipped (+ acc.skipped 1)))
      ((some k)
        (cond
          ((= kind ":sent") (if (wholeText? l) (atTurn acc k) (with acc :skipped (+ acc.skipped 1))))
          ((= kind ":reply")
            (if (wholeText? l)
              (let [(a (atTurn acc k))
                    (body (after l ":reply \""))]
                (with a :cur (with a.cur :replied true :reply (optionOr (stringSlice body 0 (max 0 (- (stringLength body) 2))) ""))))
              (with acc :skipped (+ acc.skipped 1))))
          ((= kind ":observation")
            (if (wholeText? l)
              (let [(a (atTurn acc k))] (with a :cur (with a.cur :obs (str a.cur.obs l))))
              (with acc :skipped (+ acc.skipped 1))))
          ((= kind ":error")
            (let [(a (atTurn acc k))] (with a :cur (with a.cur :error (stringReplace (tok head ":error") ":" "")))))
          (else acc)))))

fn opRow acc: Scan l: String -> Scan
  (let [(a (atTurn acc (intOf (tok l "(:op :turn"))))
        (o (Op :name (quoted l ":name") :file (quoted l ":file") :at (quoted l ":at") :status (tok l ":status") :error (tok l ":error")))]
    (with a :cur (with a.cur :ops (listAppend a.cur.ops (list o)))))

fn unitOf journal: String task: String -> String
  (let [(dir (upTo journal "/.asl/run/"))
        (base (optionOr (listLast (stringSplit dir "/")) ""))
        (words (stringSplit task " "))]
    (cond
      ((stringStartsWith? base "asex-") (optionOr (stringSlice base 5 (stringLength base)) ""))
      ((= (optionOr (listHead words) "") "plan") (optionOr (listGet words 1) ""))
      (else "")))

; (:m :do "one journal line into the scan: blank lines pass, a line that does not open with (: and close with ) is a cut or broken row and is counted in skipped, a whole row of a kind this tool does not read is passed over")
fn scanLine acc: Scan l: String -> Scan
  (let [(head (clip l 96))]
    (cond
      ((stringEmpty? (stringTrim head)) acc)
      ((or (not (stringStartsWith? l "(:")) (not (stringEndsWith? l ")"))) (with acc :skipped (+ acc.skipped 1)))
      ((stringStartsWith? head "(:turn ") (turnRow acc l head))
      ((not acc.open)
        (cond
          ((stringStartsWith? head "(:session ") (with acc :task (clip (quoted l ":task") 80)))
          ((stringStartsWith? head "(:baseline ") (with acc :baseline true))
          ((stringStartsWith? head "(:op :turn ") (opRow acc l))
          (else acc)))
      ((stringStartsWith? head "(:usage ")
        (with acc :cur (with acc.cur :inT (+ acc.cur.inT (intOf (tok head ":in"))) :cached (+ acc.cur.cached (intOf (tok head ":cached")))
                                     :outT (+ acc.cur.outT (intOf (tok head ":out"))))))
      ((stringStartsWith? head "(:op :turn ") (opRow acc l))
      ((stringStartsWith? head "(:gate :cmd ")
        (with acc :cur (with acc.cur :gateRows (+ acc.cur.gateRows 1) :gateRed (+ acc.cur.gateRed (if (stringEndsWith? l ":exit 0)") 0 1)))))
      ((stringStartsWith? head "(:served ") (if (stringEmpty? acc.alias) (with acc :alias (quoted l ":alias")) acc))
      ((stringStartsWith? head "(:providerWait ") (with acc :cur (with acc.cur :waitSec (+ acc.cur.waitSec (intOf (tok head ":sec"))))))
      ((stringStartsWith? head "(:err ") (with acc :cur (with acc.cur :error (stringReplace (tok head ":code") ":" ""))))
      ((stringStartsWith? head "(:partialReceipt ")
        (with acc :stop (quoted l ":stop") :journal (quoted l ":journal") :written (not (stringContains? l ":written ()"))))
      (else acc)))

fn closeScan acc: Scan -> Scan
  (with acc :done (listReverse (if acc.open (cons acc.cur acc.done) acc.done)) :open false)

fn scanText text: String -> Scan
  (closeScan (fold scanLine (emptyScan) (stringLines text)))

fn mutName? name: String -> Bool
  (or (= name "edit") (or (= name "write") (= name "txn")))

fn has? text: String part: String -> Bool
  (stringContains? text part)

; (:m :do "why a write, edit or txn was refused, from the turn's observation text and the op row's error code: the named classes in a fixed order, else the code itself, so a refusal this tool does not know keeps its own name")
fn rejectClass obs: String code: String -> String
  (cond
    ((or (has? obs "ERR_OWNS") (= code "ERR_OWNS")) "outsideOwns")
    ((has? obs "ERR_WRITE_WHOLE_FILE") "wholeFile")
    ((has? obs "ERR_READ_COMMENT") "comment")
    ((or (has? obs "ERR_RAW_MISSING") (= code "ERR_RAW_MISSING")) "rawMissing")
    ((or (has? obs "do not balance") (or (has? obs "unexpected closing delimiter") (has? obs "unclosed"))) "brackets")
    ((or (has? obs "ERR_NO_MATCH") (has? obs "Old target string not found")) "oldNotFound")
    ((or (has? obs "ERR_UNKNOWN_SYMBOL") (or (has? obs "ERR_UNDEFINED_EXPORT") (or (has? obs "ERR_UNRESOLVED_IMPORT") (has? obs "unbound symbol")))) "unknownSymbol")
    ((or (has? obs "ERR_TYPE_MISMATCH") (has? obs "ERR_ARITY")) "typeCheck")
    ((has? obs "ERR_PARSE") "parse")
    ((stringEmpty? code) "unknown")
    (else code))

; (:m :do "the text after the k-th step of the named op in the escaped reply, up to its closing paren: what a file-less op (query search help run) asked for")
fn stepArg reply: String name: String k: Int64 -> String
  (let [(parts (stringSplit reply (str ":op \\\"" name "\\\"")))]
    (plain (clip (upTo (optionOr (listGet parts (+ k 1)) "") ")") 160)))

fn verifyRun? arg: String -> Bool
  (or (has? arg "asl test") (or (has? arg "asl check") (or (has? arg "asl audit") (has? arg "asl run"))))

fn ran? o: Op -> Bool
  (or (= o.status "ok") (= o.error "failed"))

; (:m :do "what one op row is for the turn's class: mutOk mutRej verify read inspect err noOp unknown; a gate that ran and came back red still ran (verify), a run is a verify only when it starts an asl test, check, audit or run")
fn opKind o: Op arg: String -> String
  (cond
    ((= o.name "?") "noOp")
    ((stringEmpty? o.name) "unknown")
    ((mutName? o.name) (if (= o.status "ok") "mutOk" "mutRej"))
    ((or (= o.name "gate") (or (= o.name "check") (= o.name "test"))) (if (ran? o) "verify" "err"))
    ((= o.name "run") (if (ran? o) (if (verifyRun? arg) "verify" "inspect") "err"))
    ((or (= o.name "read") (or (= o.name "outline") (or (= o.name "query") (or (= o.name "search") (= o.name "help")))))
      (if (= o.status "ok") "read" "err"))
    ((or (= o.name "tree") (or (= o.name "gitDiff") (or (= o.name "gitLog") (or (= o.name "diff") (= o.name "note")))))
      (if (= o.status "ok") "inspect" "err"))
    ((= o.status "ok") "unknown")
    (else "err"))

fn readerCmd? word: String -> Bool
  (listContains? (list "grep" "cat" "head" "tail" "sed" "rg" "wc" "awk") word)

; (:m :do "the file a shell run reads: for grep, cat, head, tail, sed, rg, wc or awk, the last word before a pipe that is a path (has a slash or ends .asl or .asn) and is not a flag; empty for any other command")
fn runFile arg: String -> String
  (let [(words (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringReplace (upTo (after arg ":argv ") "|") "'" "") " ")))
        (paths (filter (fn [(w String)] -> Bool (and (not (stringStartsWith? w "-")) (or (has? w "/") (or (stringEndsWith? w ".asl") (stringEndsWith? w ".asn"))))) (optionOr (listTail words) (list))))]
    (if (readerCmd? (optionOr (listHead words) "")) (optionOr (listLast paths) "") ""))

fn touchedLater? turns: (List Turn) landed: (List Landed) i: Int64 file: String -> Bool
  (or (listAny? (fn [(a Landed)] -> Bool (and (> a.at i) (listContains? a.files file))) landed)
      (listAny? (fn [(j Int64)] -> Bool
                  (match (listGet turns j)
                    ((none) false)
                    ((some t) (listAny? (fn [(o Op)] -> Bool (and (= o.status "ok") (and (= o.file file) (or (= o.name "read") (= o.name "outline"))))) t.ops))))
                (range (+ i 1) (listLength turns))))

; (:m :do "a shell run that reads a file the session later reads or changes is a read of that file, judged like any other read; its :at is the command, so only the same command or an earlier whole-file read makes it a reread")
fn asRead turns: (List Turn) landed: (List Landed) i: Int64 o: Op arg: String -> Op
  (let [(file (if (and (= o.name "run") (and (ran? o) (not (verifyRun? arg)))) (runFile arg) ""))]
    (if (and (not (stringEmpty? file)) (touchedLater? turns landed i file))
      (Op :name "read" :file file :at (str "~" arg) :status "ok" :error "")
      o))

fn argsOf t: Turn -> (List String)
  (map (fn [(i Int64)] -> String
         (match (listGet t.ops i)
           ((none) "")
           ((some o)
             (if (stringEmpty? o.file)
               (stepArg t.reply o.name (listCount (fn [(p Op)] -> Bool (= p.name o.name)) (listTake t.ops i)))
               ""))))
       (range 0 (listLength t.ops)))

fn findings? t: Turn -> Bool
  (stringStartsWith? t.reply "(:findings")

fn closing? t: Turn -> Bool
  (or (stringStartsWith? t.reply "(:done") (or (stringStartsWith? t.reply "(:escalate") (stringStartsWith? t.reply "(:need")))

fn flushedOf obs: String -> (List String)
  (filter (fn [(f String)] -> Bool (not (stringEmpty? f)))
    (map plain (stringSplit (upTo (after obs ":flushed (") ")") " ")))

; (:m :do "the files a turn changed: the file of each accepted edit or write, the flushed list of an accepted txn (txn@N when the receipt names none), findings@N for a findings reply, which is the deliverable of a run that writes no file")
fn landedFiles t: Turn -> (List String)
  (let [(direct (listFlatMap (fn [(o Op)] -> (List String)
                               (if (and (= o.status "ok") (mutName? o.name))
                                 (if (= o.name "txn")
                                   (let [(fs (flushedOf t.obs))] (if (listEmpty? fs) (list (str "txn@" (n t.n))) fs))
                                   (list o.file))
                                 (list)))
                             t.ops))]
    (if (findings? t) (cons (str "findings@" (n t.n)) direct) direct))

fn landedOf turns: (List Turn) -> (List Landed)
  (listFlatMap (fn [(i Int64)] -> (List Landed)
                 (match (listGet turns i)
                   ((none) (list))
                   ((some t) (let [(fs (landedFiles t))] (if (listEmpty? fs) (list) (list (Landed :at i :files fs :reply t.reply)))))))
               (range 0 (listLength turns)))

fn stemOf file: String -> String
  (upTo (optionOr (listLast (stringSplit file "/")) "") ".")

; (:m :do "a later accepted write uses a read file when it changes that file, names its path, or names its module the way an import does (/stem followed by a space, a paren or a line end)")
fn fileUsed? later: (List Landed) file: String -> Bool
  (let [(stem (stemOf file))
        (ref (str "/" stem))]
    (listAny? (fn [(a Landed)] -> Bool
                (or (listContains? a.files file)
                  (or (has? a.reply file)
                    (and (>= (stringLength stem) 3)
                      (or (has? a.reply (str ref " ")) (or (has? a.reply (str ref ")")) (has? a.reply (str ref "\\n"))))))))
              later))

fn termOf arg: String -> String
  (let [(raw (stringTrim (upTo (after arg "'") "'")))
        (noHash (if (stringEndsWith? raw "#") (optionOr (stringSlice raw 0 (- (stringLength raw) 1)) "") raw))
        (sym (if (has? noHash "#") (after noHash "#") noHash))
        (last (optionOr (listLast (stringSplit sym "/")) ""))]
    (if (or (stringEndsWith? last ".asl") (stringEndsWith? last ".asn")) (upTo last ".") last))

; (:m :do "a query, search or help is used when its term (the last path segment or symbol, at least 3 characters) occurs in a later accepted write or in the path of a later read that was itself used; the journal does not hold what the query returned, so no closer link exists")
fn termUsed? later: (List Landed) laterReads: (List String) arg: String -> Bool
  (let [(term (termOf arg))]
    (and (>= (stringLength term) 3)
      (or (listAny? (fn [(a Landed)] -> Bool (or (has? a.reply term) (listAny? (fn [(f String)] -> Bool (has? f term)) a.files))) later)
          (listAny? (fn [(f String)] -> Bool (has? f term)) laterReads))))

fn rangeOf at: String -> (Pair Int64 Int64)
  (let [(parts (stringSplit (stringReplace at ":" "") "-"))]
    (pair (optionOr (stringToInt64 (optionOr (listGet parts 0) "")) -1) (optionOr (stringToInt64 (optionOr (listGet parts 1) "")) -1)))

fn covers? old: String new: String -> Bool
  (let [(a (rangeOf old)) (b (rangeOf new))]
    (and (>= (pairFirst a) 0) (and (>= (pairFirst b) 0) (and (<= (pairFirst a) (pairFirst b)) (>= (pairSecond a) (pairSecond b))))))

; (:m :do "a read repeats an earlier one when the same op saw the same place: the whole file, the same :at, or a line range inside an earlier range of that file; a file-less op repeats when its argument text is the same. A file changed since drops out of the seen list, so reading it again is new")
fn reread? seen: (List Seen) o: Op arg: String -> Bool
  (listAny? (fn [(s Seen)] -> Bool
              (and (= s.name o.name)
                (if (stringEmpty? o.file)
                  (and (stringEmpty? s.file) (and (not (stringEmpty? arg)) (= s.arg arg)))
                  (and (= s.file o.file) (or (stringEmpty? s.at) (or (= s.at o.at) (covers? s.at o.at)))))))
            seen)

fn usedFilesAfter turns: (List Turn) landed: (List Landed) i: Int64 -> (List String)
  (listFlatMap (fn [(j Int64)] -> (List String)
                 (match (listGet turns j)
                   ((none) (list))
                   ((some t)
                     (let [(later (filter (fn [(a Landed)] -> Bool (> a.at j)) landed))]
                       (map (fn [(o Op)] -> String o.file)
                            (filter (fn [(o Op)] -> Bool (and (= o.status "ok") (and (not (stringEmpty? o.file)) (and (or (= o.name "read") (= o.name "outline")) (fileUsed? later o.file))))) t.ops))))))
               (range (+ i 1) (listLength turns)))

fn letterOf cause: String -> String
  (cond
    ((= cause "read") "R") ((= cause "write") "W") ((= cause "gate") "G") ((= cause "findings") "F")
    ((= cause "reread") "r") ((= cause "scout") "s") ((= cause "readNoWrite") "o") ((= cause "gateFirst") "f") ((= cause "inspect") "i") ((= cause "noOp") "n")
    ((stringStartsWith? cause "rejected:") "x") ((= cause "gateSame") "g") ((stringStartsWith? cause "toolErr:") "e")
    ((= cause "wait") "w") ((= cause "close") "c") ((= cause "doneRefused") "d") ((= cause "afterGreen") "a")
    (else "u"))

fn progress? letter: String -> Bool
  (or (= letter "R") (or (= letter "W") (or (= letter "G") (= letter "F"))))

; (:m :do "the class of turn i given what the session did before it (st) and what lands after it: afterGreen once a gate was green after a write; wait for a turn the model never answered; then the best thing the turn did, write over gate over used read, else its loss in the order rejected, gateSame (gateFirst for the first gate the model asked for with nothing changed yet), reread, scout (readNoWrite in a session that lands nothing), toolErr, inspect, close (doneRefused when the run went on after a done, escalate or need reply), noOp, unknown; the (:gate ...) rows the loop writes on its own after a write or a done reply decide green but are not a gate the model asked for")
fn causeOf st: Cls t: Turn ops: (List Op) last: Bool lands: Bool kinds: (List String) rereads: (List Bool) useds: (List Bool) -> String
  (let [(kind? (fn [(k String)] -> Bool (listContains? kinds k)))
        (readAt (filter (fn [(i Int64)] -> Bool (= (optionOr (listGet kinds i) "") "read")) (range 0 (listLength kinds))))
        (fresh (filter (fn [(i Int64)] -> Bool (not (optionOr (listGet rereads i) false))) readAt))
        (usedNew (listAny? (fn [(i Int64)] -> Bool (optionOr (listGet useds i) false)) fresh))
        (gateRan (kind? "verify"))
        (bad (optionOr (listHead (filter (fn [(o Op)] -> Bool (and (!= o.status "ok") (and (!= o.error "failed") (!= o.name "?")))) ops))
                       (Op :name "" :file "" :at "" :status "" :error "")))]
    (cond
      (st.green "afterGreen")
      ((and (not t.replied) (listEmpty? t.ops)) "wait")
      ((kind? "mutOk") "write")
      ((findings? t) "findings")
      ((kind? "mutRej") (str "rejected:" (rejectClass t.obs (optionOr (listHead (map (fn [(o Op)] -> String o.error) (filter (fn [(o Op)] -> Bool (and (mutName? o.name) (!= o.status "ok"))) t.ops))) ""))))
      ((and gateRan st.changed) "gate")
      (usedNew "read")
      (gateRan (if st.verified "gateSame" "gateFirst"))
      ((and (not (listEmpty? readAt)) (listEmpty? fresh)) "reread")
      ((not (listEmpty? fresh)) (if lands "scout" "readNoWrite"))
      ((kind? "err") (str "toolErr:" (if (stringEmpty? bad.error) "unknown" bad.error)))
      ((kind? "inspect") "inspect")
      ((closing? t) (if last "close" "doneRefused"))
      ((or (kind? "noOp") (listEmpty? t.ops)) "noOp")
      (else "unknown")))

fn stepOf st: Cls turns: (List Turn) landed: (List Landed) i: Int64 t: Turn -> Cls
  (let [(args (argsOf t))
        (ops (map (fn [(j Int64)] -> Op (match (listGet t.ops j) ((some o) (asRead turns landed i o (optionOr (listGet args j) ""))) ((none) (Op :name "" :file "" :at "" :status "" :error "")))) (range 0 (listLength t.ops))))
        (kinds (map (fn [(j Int64)] -> String (match (listGet ops j) ((some o) (opKind o (optionOr (listGet args j) ""))) ((none) "unknown"))) (range 0 (listLength ops))))
        (later (filter (fn [(a Landed)] -> Bool (> a.at i)) landed))
        (laterReads (usedFilesAfter turns landed i))
        (rereads (map (fn [(j Int64)] -> Bool (match (listGet ops j) ((some o) (reread? st.seen o (optionOr (listGet args j) ""))) ((none) false))) (range 0 (listLength t.ops))))
        (useds (map (fn [(j Int64)] -> Bool
                      (match (listGet ops j)
                        ((none) false)
                        ((some o) (if (stringEmpty? o.file) (termUsed? later laterReads (optionOr (listGet args j) "")) (fileUsed? later o.file)))))
                    (range 0 (listLength t.ops))))
        (cause (causeOf st t ops (= (+ i 1) (listLength turns)) (not (listEmpty? landed)) kinds rereads useds))
        (mine (landedFiles t))
        (wrote (listContains? kinds "mutOk"))
        (gateRan (listContains? kinds "verify"))
        (greenNow (and (or gateRan (> t.gateRows 0)) (and (= t.gateRed 0) (not (listAny? (fn [(o Op)] -> Bool (= o.error "failed")) t.ops)))))
        (rejected (if wrote (listCount (fn [(k String)] -> Bool (= k "mutRej")) kinds) 0))
        (newSeen (listFlatMap (fn [(j Int64)] -> (List Seen)
                                (match (listGet ops j)
                                  ((none) (list))
                                  ((some o) (if (= (optionOr (listGet kinds j) "") "read") (list (Seen :name o.name :file o.file :at o.at :arg (optionOr (listGet args j) ""))) (list)))))
                              (range 0 (listLength t.ops))))
        (kept (filter (fn [(s Seen)] -> Bool (not (listContains? mine s.file))) (listAppend st.seen newSeen)))
        (step (Step :turn t.n :letter (letterOf cause) :cause cause :inT t.inT :outT t.outT :cached t.cached :rejectedOps rejected
                    :preview (clip (plain (clip (if t.replied t.reply (if (stringEmpty? t.error) "" (str "error " t.error))) 240)) 80)))]
    (Cls :seen kept
         :changed (if gateRan false (or st.changed wrote))
         :verified (or st.verified gateRan)
         :anyMut (or st.anyMut wrote)
         :green (or st.green (and greenNow (or st.anyMut wrote)))
         :autoGate (or st.autoGate (and wrote (and (> t.gateRows 0) (not gateRan))))
         :files (fold (fn [(acc (List String)) (f String)] -> (List String) (if (listContains? acc f) acc (cons f acc))) st.files (if st.green (list) mine))
         :firstWrite (if (and (= st.firstWrite 0) wrote) (+ i 1) st.firstWrite)
         :steps (cons step st.steps)))

fn classify turns: (List Turn) -> Cls
  (let [(landed (landedOf turns))]
    (fold (fn [(st Cls) (i Int64)] -> Cls (match (listGet turns i) ((some t) (stepOf st turns landed i t)) ((none) st)))
          (Cls :seen (list) :changed false :verified false :anyMut false :green false :autoGate false :files (list) :firstWrite 0 :steps (list))
          (range 0 (listLength turns))))

fn lettersOf steps: (List Step) letter: String -> Int64
  (listCount (fn [(s Step)] -> Bool (= s.letter letter)) steps)

fn sumOf steps: (List Step) pick: (fn [Step] -> Int64) -> Int64
  (fold (fn [(acc Int64) (s Step)] -> Int64 (+ acc (pick s))) 0 steps)

; (:m :do "one session's path from its journal text: written when the receipt lists written files and the run stopped ok, else failed with the stop word (noWrite for an ok stop that wrote nothing, noReceipt for a journal that ends without one); a session with an accepted write has ideal = its used-read turns, two at most, plus one per written file plus one gate turn unless the loop wrote (:gate ...) rows on a write turn without a gate op, which is the loop gating by itself; without an accepted write ideal and excess stay 0 and are not printed")
fn pathOfText session: String text: String -> Path
  (let [(sc (scanText text))
        (c (classify sc.done))
        (steps (listReverse c.steps))
        (stop (if (stringEmpty? sc.stop) "noReceipt" sc.stop))
        (outcome (if (and sc.written (= stop "ok")) "written" (str "failed:" (if (= stop "ok") "noWrite" stop))))
        (wrote (> c.firstWrite 0))
        (ideal (if wrote (+ (+ (min 2 (lettersOf steps "R")) (listLength c.files)) (if c.autoGate 0 1)) 0))
        (turns (listLength steps))]
    (Path :session session :unit (unitOf sc.journal sc.task) :model (if (stringEmpty? sc.alias) "unknown" sc.alias) :turns turns :outcome outcome
          :inT (sumOf steps (fn [(s Step)] -> Int64 s.inT)) :outT (sumOf steps (fn [(s Step)] -> Int64 s.outT)) :cached (sumOf steps (fn [(s Step)] -> Int64 s.cached))
          :shape (stringJoin (map (fn [(s Step)] -> String s.letter) steps) "") :firstWriteTurn c.firstWrite
          :wrote wrote :files (listLength c.files) :ideal ideal :excess (if wrote (- turns ideal) 0) :skipped sc.skipped :steps steps))

fn distinct xs: (List String) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (cons x acc))) (list) xs))

fn tallyBy keys: (List String) steps: (List Step) -> (List Tally)
  (listSortBy (fn [(t Tally)] -> Int64 (- 0 t.outT))
    (map (fn [(k String)] -> Tally
           (let [(mine (listFlatMap (fn [(i Int64)] -> (List Step) (if (= (optionOr (listGet keys i) "") k) (match (listGet steps i) ((some s) (list s)) ((none) (list))) (list))) (range 0 (listLength keys))))]
             (Tally :key k :turns (listLength mine) :inT (sumOf mine (fn [(s Step)] -> Int64 s.inT)) :outT (sumOf mine (fn [(s Step)] -> Int64 s.outT)))))
         (listSort (distinct keys))))

fn pct part: Int64 whole: Int64 -> String
  (if (<= whole 0) "0.0"
    (let [(tenths (/ (+ (* part 2000) whole) (* whole 2)))] (str (n (/ tenths 10)) "." (n (mod tenths 10)))))

fn wasteField steps: (List Step) -> String
  (let [(lost (filter (fn [(s Step)] -> Bool (not (progress? s.letter))) steps))
        (rows (tallyBy (map (fn [(s Step)] -> String s.cause) lost) lost))]
    (str "(" (stringJoin (map (fn [(t Tally)] -> String (str "(" t.key " " (n t.turns) ")")) rows) " ") ")"))

fn pathLine p: Path -> String
  (str "(:path :session \"" p.session "\" :unit \"" p.unit "\" :model \"" p.model "\" :turns " (n p.turns) " :outcome " p.outcome
       " :in " (n p.inT) " :out " (n p.outT) " :cached " (n p.cached) " :shape \"" p.shape "\" :firstWriteTurn " (n p.firstWriteTurn)
       (if p.wrote (str " :ideal " (n p.ideal) " :excess " (n p.excess)) "") " :waste " (wasteField p.steps) " :skipped " (n p.skipped) ")")

fn stepLine s: Step -> String
  (str "(:step :turn " (n s.turn) " :class " (if (progress? s.letter) "progress" "waste") " :letter " s.letter " :cause " s.cause
       " :in " (n s.inT) " :out " (n s.outT) " :cached " (n s.cached) (if (> s.rejectedOps 0) (str " :rejectedOps " (n s.rejectedOps)) "") " :op \"" s.preview "\")")

; (:m :do "nearest-rank percentile of a list, 0 for none")
fn rankOf xs: (List Int64) percent: Int64 -> Int64
  (let [(sorted (listSort xs)) (count (listLength sorted))]
    (if (= count 0) 0 (optionOr (listGet sorted (max 0 (- (/ (+ (* count percent) 99) 100) 1))) 0)))

fn groupLine tag: String keyName: String key: String ps: (List Path) -> String
  (let [(written (listCount (fn [(p Path)] -> Bool (= p.outcome "written")) ps))
        (wrote (filter (fn [(p Path)] -> Bool p.wrote) ps))
        (short (listCount (fn [(p Path)] -> Bool (<= p.excess 1)) wrote))
        (sumP (fn [(pick (fn [Path] -> Int64))] -> Int64 (fold (fn [(acc Int64) (p Path)] -> Int64 (+ acc (pick p))) 0 ps)))]
    (str "(" tag " " keyName " " key " :sessions " (n (listLength ps)) " :written " (n written) " :wrote " (n (listLength wrote)) " :short " (n short)
         " :turns " (n (sumP (fn [(p Path)] -> Int64 p.turns))) " :medianExcess " (n (rankOf (map (fn [(p Path)] -> Int64 p.excess) wrote) 50))
         " :in " (n (sumP (fn [(p Path)] -> Int64 p.inT))) " :out " (n (sumP (fn [(p Path)] -> Int64 p.outT))) ")"))

; (:m :do "progress turns a tighter path would not have needed: in sessions that landed a write, used-read turns beyond two, since one reply can carry every read, and accepted-write turns beyond one per written file")
fn batchLine ps: (List Path) -> String
  (let [(reads (fold (fn [(acc Int64) (p Path)] -> Int64 (+ acc (max 0 (- (lettersOf p.steps "R") 2)))) 0 ps))
        (writes (fold (fn [(acc Int64) (p Path)] -> Int64
                        (+ acc (max 0 (- (lettersOf p.steps "W") p.files))))
                      0 ps))]
    (str "(:batchable :readTurns " (n reads) " :writeTurns " (n writes) ")"))

; (:m :do "the totals over sessions: one (:progress ...) row and one (:waste ...) row per cause, by lost output tokens descending, whose turns add up to all turns (the mixedRejected row counts turns already under progress); then sessions by model and by outcome, the no-write sessions apart, and over the sessions that landed a write the spread of the first write turn and of excess and the share within one turn of the ideal path")
; (:m :do "sessions without an accepted write have no ideal path; they are counted apart with their turns, output tokens and stop words")
fn noWriteLine ps: (List Path) -> String
  (let [(stops (map (fn [(p Path)] -> String (stringReplace p.outcome "failed:" "")) ps))]
    (str "(:noWrite :sessions " (n (listLength ps)) " :turns " (n (fold (fn [(acc Int64) (p Path)] -> Int64 (+ acc p.turns)) 0 ps))
         " :out " (n (fold (fn [(acc Int64) (p Path)] -> Int64 (+ acc p.outT)) 0 ps))
         " :byStop (" (stringJoin (map (fn [(k String)] -> String (str "(" k " " (n (listCount (fn [(x String)] -> Bool (= x k)) stops)) ")")) (listSort (distinct stops))) " ") "))"))

; (:m :do "write turns that also carried a refused write: the turn and its tokens stay with progress, this row only counts such turns and their refused ops")
fn mixedLine steps: (List Step) -> (List String)
  (let [(mixed (filter (fn [(s Step)] -> Bool (> s.rejectedOps 0)) steps))]
    (if (listEmpty? mixed) (list)
      (list (str "(:waste :cause mixedRejected :turns " (n (listLength mixed)) " :rejectedOps " (n (fold (fn [(acc Int64) (s Step)] -> Int64 (+ acc s.rejectedOps)) 0 mixed)) " :countedIn progress)"))))

fn summaryText ps: (List Path) skipped: Int64 -> String
  (let [(steps (listFlatMap (fn [(p Path)] -> (List Step) p.steps) ps))
        (total (listLength steps))
        (good (filter (fn [(s Step)] -> Bool (progress? s.letter)) steps))
        (lost (filter (fn [(s Step)] -> Bool (not (progress? s.letter))) steps))
        (rows (tallyBy (map (fn [(s Step)] -> String s.cause) lost) lost))
        (firsts (map (fn [(p Path)] -> Int64 p.firstWriteTurn) (filter (fn [(p Path)] -> Bool (> p.firstWriteTurn 0)) ps)))
        (wrote (filter (fn [(p Path)] -> Bool p.wrote) ps))
        (excess (map (fn [(p Path)] -> Int64 p.excess) wrote))
        (short (listCount (fn [(p Path)] -> Bool (<= p.excess 1)) wrote))
        (models (listSort (distinct (map (fn [(p Path)] -> String p.model) ps))))
        (outcomes (listSort (distinct (map (fn [(p Path)] -> String p.outcome) ps))))]
    (stringJoin
      (listAppend
        (list
          (str "(:turnPath :sessions " (n (listLength ps)) " :turns " (n total) " :skipped " (n skipped)
               " :in " (n (sumOf steps (fn [(s Step)] -> Int64 s.inT))) " :out " (n (sumOf steps (fn [(s Step)] -> Int64 s.outT))) ")")
          (str "(:progress :turns " (n (listLength good)) " :sharePct " (pct (listLength good) total)
               " :out " (n (sumOf good (fn [(s Step)] -> Int64 s.outT))) " :in " (n (sumOf good (fn [(s Step)] -> Int64 s.inT))) ")"))
        (listAppend
          (map (fn [(t Tally)] -> String
                 (str "(:waste :cause " t.key " :turns " (n t.turns) " :sharePct " (pct t.turns total) " :out " (n t.outT) " :in " (n t.inT) ")"))
               rows)
          (listAppend (mixedLine steps) (listAppend
            (map (fn [(m String)] -> String (groupLine ":byModel" ":model" (str "\"" m "\"") (filter (fn [(p Path)] -> Bool (= p.model m)) ps))) models)
            (listAppend
              (map (fn [(o String)] -> String (groupLine ":byOutcome" ":outcome" o (filter (fn [(p Path)] -> Bool (= p.outcome o)) ps))) outcomes)
              (list
                (str "(:letters " (stringJoin (map (fn [(l String)] -> String (str "(" l " " (n (lettersOf steps l)) ")")) (listSort (distinct (map (fn [(s Step)] -> String s.letter) steps)))) " ") ")")
                (batchLine wrote)
                (noWriteLine (filter (fn [(p Path)] -> Bool (not p.wrote)) ps))
                (str "(:firstWriteTurn :sessions " (n (listLength firsts)) " :median " (n (rankOf firsts 50)) " :p90 " (n (rankOf firsts 90)) ")")
                (str "(:excess :sessions " (n (listLength excess)) " :median " (n (rankOf excess 50)) " :p90 " (n (rankOf excess 90)) ")")
                (str "(:shortPath :sessions " (n short) " :wrote " (n (listLength wrote)) " :all " (n (listLength ps))
                     " :shareOfWrotePct " (pct short (listLength wrote)) " :shareOfAllPct " (pct short (listLength ps)) ")")))))))
      "\n"))

fn recent? path: String sinceHours: Int64 nowS: Int64 -> Bool
  (if (<= sinceHours 0) true
    (match (fileStat path)
      ((ok st) (>= st.mtime (- nowS (* sinceHours 3600))))
      ((err _) false)))

fn addPath acc: Loaded p: Path -> Loaded
  (if (= p.turns 0)
    (Loaded :paths acc.paths :unreadable acc.unreadable :empty (+ acc.empty 1) :skipped (+ acc.skipped p.skipped))
    (Loaded :paths (listAppend acc.paths (list p)) :unreadable acc.unreadable :empty acc.empty :skipped (+ acc.skipped p.skipped)))

; (:m :do "a journal that holds no turn (empty, or nothing but broken rows) is not a session: it is counted in empty and stays out of every total and median")
fn ! pathsIn dir: String names: (List String) -> Loaded
  (fold (fn [(acc Loaded) (name String)] -> Loaded
          (match (fileReadString (str dir "/" name))
            ((err _) (Loaded :paths acc.paths :unreadable (+ acc.unreadable 1) :empty acc.empty :skipped acc.skipped))
            ((ok text) (addPath acc (pathOfText (stringReplace name ".journal" "") text)))))
        (Loaded :paths (list) :unreadable 0 :empty 0 :skipped 0) names)

; (:m :do "the report for a journal directory as (exit code, text): --session prints that session's path and one row per turn; otherwise the summary and the top paths, by excess for sessions that landed a write and by turns for the rest. A directory without journals is one plain row and code 0, an unreadable one is code 1; a file that cannot be read as text is counted in :unreadable and the rest go on")
fn ! reportDir dir: String sinceHours: Int64 top: Int64 session: String nowS: Int64 -> (Pair Int64 String)
  (match (dirList dir)
    ((err _) (pair 1 (str "(:turnPath :dir \"" dir "\" :error \"directory unreadable\")")))
    ((ok all)
      (let [(names (listSort (filter (fn [(f String)] -> Bool (and (stringEndsWith? f ".journal") (recent? (str dir "/" f) sinceHours nowS))) all)))]
        (if (listEmpty? names)
          (pair 0 (str "(:turnPath :dir \"" dir "\" :sessions 0 :note \"no *.journal file" (if (> sinceHours 0) (str " in the last " (n sinceHours) " hours") "") "\")"))
          (if (stringEmpty? session)
            (let [(got (pathsIn dir names))
                  (ps got.paths)
                  (ranked (listSortBy (fn [(p Path)] -> Int64 (- 0 (if p.wrote p.excess p.turns))) ps))
                  (shown (if (> top 0) (listTake ranked top) ranked))]
              (pair 0 (str (summaryText ps got.skipped) "\n(:files :read " (n (listLength ps)) " :unreadable " (n got.unreadable) " :empty " (n got.empty) ")\n"
                           (stringJoin (map pathLine shown) "\n"))))
            (let [(mine (filter (fn [(f String)] -> Bool (stringStartsWith? f session)) names))]
              (match (listHead mine)
                ((none) (pair 1 (str "(:turnPath :dir \"" dir "\" :session \"" session "\" :error \"no such session\")")))
                ((some name)
                  (let [(got (pathsIn dir (list name)))]
                    (match (listHead got.paths)
                      ((none) (pair 1 (str "(:turnPath :dir \"" dir "\" :session \"" session "\" :error \"journal unreadable or without a turn\")")))
                      ((some p) (pair 0 (str (pathLine p) "\n" (stringJoin (map stepLine p.steps) "\n"))))))))))))))

fn flagVal args: (List String) name: String -> String
  (match (listIndexOf args name)
    ((some i) (optionOr (listGet args (+ i 1)) ""))
    ((none) ""))

fn dirArg args: (List String) -> String
  (optionOr
    (listHead (listFlatMap (fn [(i Int64)] -> (List String)
                             (let [(a (optionOr (listGet args i) ""))
                                   (prev (if (> i 0) (optionOr (listGet args (- i 1)) "") ""))]
                               (if (or (stringStartsWith? a "--") (or (stringStartsWith? prev "--") (stringEndsWith? a ".asl"))) (list) (list a))))
                           (range 0 (listLength args))))
    "")

fn ! main args: (List String) -> (Result Int64 String)
  (let [(dir (dirArg args))
        (hoursText (flagVal args "--since-hours"))
        (topText (flagVal args "--top"))
        (hours (if (stringEmpty? hoursText) (some 0) (stringToInt64 hoursText)))
        (top (if (stringEmpty? topText) (some 10) (stringToInt64 topText)))]
    (if (or (stringEmpty? dir) (or (none? hours) (none? top)))
      (let [(_ (println "(:turnPath :usage \"run turnPath.asl DIR [--since-hours N] [--top K] [--session ID]\")"))] (ok 2))
      (let [(r (reportDir dir (optionOr hours 0) (optionOr top 10) (flagVal args "--session") (/ (nowNs) 1000000000)))
            (_ (println (pairSecond r)))]
        (ok (pairFirst r)))))
