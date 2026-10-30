(module asl-tools/audit/run
  :x [Lens AuditCfg Finding RunOut segs parseConfig scanText promptOf real? flagged? rowsFor heldBy git! rangeFiles! run! main]
  :i [(tools/fleet/model :a fm) (asl-tools/fleet/run :a fr) (asl-tools/coord/store :a st) (asl-tools/coord/planImport :a pi) (asl-tools/coord/reviewStage :a rs) (asl-parser/reader :a rd)])

; (:m :ref AUD-RUN :do "the release audit loop as one command: ~/.asl/audit.asn names the lenses, their models and consensus rule; the range runs from the last release tag (or :since) to HEAD; static lenses find candidates, models vote on bounded code slices, flagged findings of :queue true lenses become (:u ...) rows that are imported dry, then for real; one (:auditRun ...) row per run")

(schema Lens (:f name String) (:f queue Bool) (:f models (List String)) (:f rule String))

(schema AuditCfg (:f out String) (:f since String) (:f lenses (List Lens)) (:f slice Int64) (:f store String) (:f plans (List String)))

(schema Finding (:f id String) (:f lens String) (:f file String) (:f line Int64) (:f symbol String) (:f ret String) (:f severity String) (:f claim String) (:f evidence String))

(schema RunOut (:f summary String) (:f rows String) (:f findings (List Finding)) (:f flagged (List Finding)))

fn lensNames -> (List String)
  (list "knob" "swallow" "stub")

fn topKeys -> (List String)
  (list ":v" ":out" ":since" ":lenses" ":slice" ":store" ":plans")

fn lensKeys -> (List String)
  (list ":lens" ":queue" ":models" ":rule")

; (:m :do "keys of a :k v :k v run from START: 1 skips a bare tag like :audit, 0 keeps a keyed head like (:lens knob ...); values are never read as keys")
fn keysOf items: (List rd/SExpr) i: Int64 acc: (List String) -> (List String)
  (match (listGet items i)
    ((none) (listReverse acc))
    ((some k) (keysOf items (+ i 2) (cons (fm/atomText k) acc))))

fn unknownKey items: (List rd/SExpr) start: Int64 allowed: (List String) -> (Option String)
  (listFind (fn [(k String)] -> Bool (not (listContains? allowed k))) (keysOf items start (list)))

fn textAt items: (List rd/SExpr) key: String fallback: String -> String
  (match (fm/kvGet items key) ((none) fallback) ((some v) (fm/textOf v)))

fn lensOf s: rd/SExpr -> (Result Lens String)
  (let [(items (fm/itemsOf s))
        (name (textAt items ":lens" ""))
        (rule (textAt items ":rule" "any"))
        (models (match (fm/kvGet items ":models") ((none) (list)) ((some v) (fm/atomsOf v))))]
    (match (unknownKey items 0 (lensKeys))
      ((some k) (err (str "audit config: lens " name ": unknown key " k)))
      ((none)
        (cond
          ((not (listContains? (lensNames) name)) (err (str "audit config: unknown lens " (fm/asnQuote name) ", known: knob swallow stub")))
          ((not (or (= rule "all") (= rule "any"))) (err (str "audit config: lens " name ": :rule must be all or any, got " rule)))
          ((listEmpty? models) (err (str "audit config: lens " name ": :models is empty")))
          (else (ok (Lens :name name :queue (= (textAt items ":queue" "false") "true") :models models :rule rule)))))))

fn collectLenses xs: (List rd/SExpr) acc: (List Lens) -> (Result (List Lens) String)
  (match (listHead xs)
    ((none) (ok (listReverse acc)))
    ((some x) (match (lensOf x) ((err e) (err e)) ((ok l) (collectLenses (optionOr (listTail xs) (list)) (cons l acc))))))

; (:m :do "the first (:audit ...) form of the text; an unknown key at the top or in a lens row is an error, so a typo never silently drops a setting")
fn parseConfig text: String -> (Result AuditCfg String)
  (match (fm/parseForms text)
    ((err e) (err (str "audit config: " e)))
    ((ok forms)
      (match (listFind (fn [(f rd/SExpr)] -> Bool (= (fm/atomText (optionOr (listHead (fm/itemsOf f)) (rd/sexprAtom ""))) ":audit")) forms)
        ((none) (err "audit config: no (:audit ...) form"))
        ((some form)
          (let [(items (fm/itemsOf form))]
            (match (unknownKey items 1 (topKeys))
              ((some k) (err (str "audit config: unknown key " k)))
              ((none)
                (match (collectLenses (match (fm/kvGet items ":lenses") ((none) (list)) ((some v) (fm/itemsOf v))) (list))
                  ((err e) (err e))
                  ((ok lenses)
                    (if (listEmpty? lenses) (err "audit config: :lenses is empty")
                      (ok (AuditCfg :out (textAt items ":out" "~/.asl/run/audit/<version>/") :since (textAt items ":since" "")
                                    :lenses lenses :slice (optionOr (fm/intOf (fm/kvGet items ":slice")) 8) :store (textAt items ":store" "~/.asl/run/conductor") :plans (match (fm/kvGet items ":plans") ((none) (list)) ((some v) (fm/atomsOf v)))))))))))))))

fn after s: String pat: String -> (Option String)
  (match (stringIndexOf s pat)
    ((none) (none))
    ((some i) (stringSlice s (+ i (stringLength pat)) (stringLength s))))

fn containsAny? s: String pats: (List String) -> Bool
  (listAny? (fn [(p String)] -> Bool (stringContains? s p)) pats)

fn startsAny? s: String pats: (List String) -> Bool
  (listAny? (fn [(p String)] -> Bool (stringStartsWith? s p)) pats)

fn header? line: String -> Bool
  (startsAny? line (list "fn " "pub fn " "defn " "pub defn "))

fn headerName line: String -> String
  (let [(rest (stringTrim (optionOr (after line "fn ") line)))
        (bare (if (stringStartsWith? rest "! ") (optionOr (stringSlice rest 2 (stringLength rest)) rest) rest))]
    (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit bare " ")) "") "[")) "") "(")) ""))

fn headerRet line: String -> String
  (optionOr (after line " -> ") "")

fn lower? c: String -> Bool
  (and (not (stringEmpty? c)) (stringContains? "abcdefghijklmnopqrstuvwxyz" c))

fn alnum? c: String -> Bool
  (and (not (stringEmpty? c)) (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" c))

; (:m :do "x starts with an identifier closed by a paren: the arm returns a fold accumulator unchanged")
fn accArm? x: String -> Bool
  (match (stringIndexOf x ")")
    ((none) false)
    ((some i) (let [(name (optionOr (stringSlice x 0 i) ""))]
                (and (> i 0) (and (lower? (optionOr (stringSlice name 0 1) ""))
                                  (listAll? alnum? (map (fn [(k Int64)] -> String (optionOr (stringSlice name k (+ k 1)) "")) (range 0 i))))))))

fn swallowOf sym: String ret: String line: String -> (Option (Pair String String))
  (match (after line "((err _) ")
    ((none) (none))
    ((some x)
      (let [(pred (or (stringEndsWith? sym "?") (or (stringStartsWith? ret "Bool") (stringStartsWith? ret "(Option"))))
            (prop (or (startsAny? x (list "(err " "(none)" "none" "false"))
                      (containsAny? x (list "err" "Err" "fail" "Fail" "warn" "Warn" "log" "Log" "die" "panic" "eprint" "stderr" "eport" "exit" "refus"))))]
        (cond
          ((or pred prop) (none))
          ((and (stringStartsWith? ret "(Result") (stringStartsWith? x "(ok ")) (some (pair "medium" "Result fn turns an error into ok with a default")))
          ((accArm? x) (some (pair "medium" "fold/loop arm drops the failed item and keeps the accumulator")))
          ((startsAny? ret (list "Int" "I64" "String" "Str" "(List")) (some (pair "low" "error mapped to a plain default value")))
          (else (none))))))

fn modelFamilies -> (List String)
  (list "gemini" "claude" "gpt" "deepseek" "glm" "qwen" "kimi" "gemma" "llama")

fn knobOf line: String -> (Option (Pair String String))
  (cond
    ((stringContains? line "(:m ") (none))
    ((match (after line "Access-Control-Allow-Origin: ") ((some r) (or (lower? (optionOr (stringSlice r 0 1) "")) (stringStartsWith? r "*"))) ((none) false)) (some (pair "medium" "fixed CORS origin")))
    ((containsAny? line (list "\"127.0.0.1" "\"localhost" "\"0.0.0.0")) (some (pair "medium" "hardcoded host/port")))
    ((containsAny? line (list "\"/Users/" "\"/home/" "\"/opt/")) (some (pair "medium" "hardcoded absolute user path")))
    ((containsAny? line (map (fn [(f String)] -> String (str "\"" f "-")) (modelFamilies))) (some (pair "medium" "hardcoded model id")))
    ((and (containsAny? line (list "\"http://" "\"https://")) (not (containsAny? line (list "example.com" "example.org" "github.com" "w3.org" "schema")))) (some (pair "low" "hardcoded endpoint url")))
    (else (none)))

fn stubOf comment: Bool line: String -> (Option (Pair String String))
  (cond
    (comment (if (and (not (stringContains? line "(:m ")) (containsAny? line (list "TODO" "FIXME" "HACK"))) (some (pair "low" "unfinished-work marker in a comment")) (none)))
    ((and (containsAny? line (list "not yet implemented" "Not yet implemented" "Unimplemented:" "unimplemented:")) (not (stringContains? line "ERR_UNIMPLEMENTED"))) (some (pair "medium" "path reports itself unimplemented")))
    (else (none)))

(schema ScanSt (:f sym String) (:f ret String) (:f n Int64) (:f found (List Finding)))

fn clip s: String -> String
  (let [(t (stringTrim s))] (if (> (stringLength t) 170) (optionOr (stringSlice t 0 170) t) t))

fn hit st0: ScanSt file: String lens: String on: (List String) h: (Option (Pair String String)) line: String -> ScanSt
  (match h
    ((none) st0)
    ((some p)
      (if (not (listContains? on lens)) st0
        (with st0 :found (cons (Finding :id "" :lens lens :file file :line st0.n :symbol st0.sym :ret st0.ret :severity (pairFirst p) :claim (pairSecond p) :evidence (clip line)) st0.found)))))

; (:m :do "static lenses over one file; ids are given later in run order; on lists the enabled lens names")
fn scanText file: String text: String on: (List String) -> (List Finding)
  (let [(end (fold (fn [(s ScanSt) (line String)] -> ScanSt
                     (let [(s1 (with s :n (+ s.n 1)))
                           (s2 (if (header? line) (with s1 :sym (headerName line) :ret (headerRet line)) s1))
                           (comment (stringStartsWith? (stringTrim line) ";"))]
                       (if comment (hit s2 file "stub" on (stubOf true line) line)
                         (hit (hit (hit s2 file "stub" on (stubOf false line) line) file "swallow" on (swallowOf s2.sym s2.ret line) line) file "knob" on (knobOf line) line))))
                   (ScanSt :sym "" :ret "" :n 0 :found (list)) (stringLines text)))]
    (listReverse end.found))

fn ruleText lens: String -> String
  (cond
    ((= lens "swallow") "Rule: an error must be propagated, reported or deliberately mapped; a defect is an error silently turned into a normal-looking result that hides a failure from the caller or user. Mapping 'file absent' to an empty value on purpose is not a defect.")
    ((= lens "knob") "Rule: settings-first: endpoints, hosts, ports, model ids and user paths belong in config files (workspace or ~/.asl), not in code; a default inside a settings schema or a test fixture is not a defect.")
    (else "Rule: no stubs or unfinished paths in production code."))

; (:m :do "the prompt carries only the rule, the finding and the numbered code slice line +-k of an asl/ source file: never ledger content or env values")
fn promptOf f: Finding text: String k: Int64 -> String
  (let [(ls (stringLines text))
        (a (if (> f.line k) (- f.line k) 1))
        (b (+ f.line k))
        (hdr (fold (fn [(h String) (i Int64)] -> String (let [(l (optionOr (listGet ls (- i 1)) ""))] (if (header? l) l h))) "" (range 1 (+ f.line 1))))
        (slice (map (fn [(i Int64)] -> String (str (stringFromInt64 i) "| " (optionOr (listGet ls (- i 1)) ""))) (filter (fn [(i Int64)] -> Bool (<= i (listLength ls))) (range a (+ b 1)))))]
    (stringJoin (listAppend (list "Audit check. Decide whether this static finding is a real defect worth a fix task, or a false positive."
                                  (ruleText f.lens)
                                  (str "Finding: lens=" f.lens " claim=\"" f.claim "\" file=" f.file " line=" (stringFromInt64 f.line))
                                  (str "Enclosing fn header: " (clip hdr))
                                  (str "Code (lines " (stringFromInt64 a) "-" (stringFromInt64 b) "):"))
                            (listAppend slice (list (str "Reply with exactly one line: (:verdict :id " f.id " :real true|false :severity high|medium|low :why \"<= 25 words\")"))))
                "\n"))

fn real? reply: String -> Bool
  (stringContains? reply ":real true")

; (:m :do "consensus: rule all needs every model to answer :real true, any needs one; a failed call is a no vote")
fn flagged? l: Lens votes: (List Bool) -> Bool
  (if (= l.rule "all") (and (not (listEmpty? votes)) (listAll? (fn [(v Bool)] -> Bool v) votes)) (listAny? (fn [(v Bool)] -> Bool v) votes))

fn segs path: String -> (List String)
  (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit path "/"))

fn baseName path: String -> String
  (let [(b (optionOr (listLast (segs path)) path))] (if (stringEndsWith? b ".asl") (optionOr (stringSlice b 0 (- (stringLength b) 4)) b) b))

; (:m :do "the gate test a fix unit writes: <dir>/tests/<base>AuditTest.asl beside the src dir for packages, beside the file for tools")
fn testPath file: String -> String
  (let [(ss (segs file))
        (dirSegs (listTake ss (- (listLength ss) 1)))
        (pkgSegs (if (= (optionOr (listLast dirSegs) "") "src") (listTake dirSegs (- (listLength dirSegs) 1)) dirSegs))]
    (str (stringJoin pkgSegs "/") "/tests/" (baseName file) "AuditTest.asl"))

fn idPart s: String -> String
  (stringJoin (filter alnum? (map (fn [(k Int64)] -> String (optionOr (stringSlice s k (+ k 1)) "")) (range 0 (stringLength s)))) "")

fn unitId tag: String file: String -> String
  (let [(ss (segs file)) (n (listLength ss))
        (pkg (optionOr (listGet ss (if (= (optionOr (listGet ss (- n 2)) "") "src") (- n 3) (- n 2))) ""))]
    (str "AUD-" (idPart tag) "-" (idPart pkg) "-" (idPart (baseName file))))

; (:m :do "one (:u ...) row per file of flagged findings in queue lenses; the id is stable per tag and file, so a rerun is skipped by the import")
fn rowsFor tag: String head: String fs: (List Finding) -> String
  (let [(files (fold (fn [(acc (List String)) (f Finding)] -> (List String) (if (listContains? acc f.file) acc (listAppend acc (list f.file)))) (list) fs))]
    (stringJoin (map (fn [(file String)] -> String
                       (let [(mine (filter (fn [(f Finding)] -> Bool (= f.file file)) fs))
                             (t (testPath file))
                             (claims (stringJoin (map (fn [(f Finding)] -> String (str f.lens " line " (stringFromInt64 f.line) " " f.symbol ": " f.claim " [" f.evidence "]")) mine) "; "))]
                         (str "(:u :id " (unitId tag file) " :queue conductor :src auditRun :owns (" (fm/asnQuote file) " " (fm/asnQuote t) ") :gate " (fm/asnQuote (str "./bin/asl test " t))
                              " :do " (fm/asnQuote (str "audit " tag ".." head " in " file ": " claims ". Fix each, or leave a one-line (:m ...) why when it is intended; " t " goes red before the fix and green after")) ")")))
                     files)
                "\n"))

; (:m :ref AUD-RUN-DEDUPE :do "open owners of files: store tasks whose cond row (or, without one, the task itself) is not merged, done or dropped, and (:u ...) rows of the store's ledger.path and of :plans whose :status is none of those")
fn closed? s: String -> Bool
  (listContains? (list "merged" "done" "dropped") s)

fn ! condSt! store: String id: String -> String
  (match (fileReadString (str store "/cond/" id ".asn"))
    ((err _) "")
    ((ok t) (match (fm/parseForms t)
              ((err _) "")
              ((ok forms) (match (listHead forms) ((none) "") ((some f) (textAt (fm/itemsOf f) ":st" "")))))))

fn ownsOf items: (List rd/SExpr) -> (List String)
  (match (fm/kvGet items ":owns")
    ((none) (list))
    ((some v) (let [(xs (fm/atomsOf v))] (if (listEmpty? xs) (list (fm/textOf v)) xs))))

fn pairsOf owns: (List String) id: String -> (List (Pair String String))
  (map (fn [(o String)] -> (Pair String String) (pair o id)) owns)

fn ! storeOwners! store: String -> (List (Pair String String))
  (match (st/readUnits! store)
    ((err _) (list))
    ((ok us) (fold (fn [(acc (List (Pair String String))) (u st/Task)] -> (List (Pair String String))
                     (let [(c (condSt! store u.id))]
                       (if (closed? (if (stringEmpty? c) u.st c)) acc (listAppend acc (pairsOf u.owns u.id)))))
                   (list) us)))

fn planOwners text: String -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (line String)] -> (List (Pair String String))
          (if (not (stringStartsWith? line "(:u :id ")) acc
            (match (fm/parseForms line)
              ((err _) acc)
              ((ok forms)
                (match (listHead forms)
                  ((none) acc)
                  ((some f)
                    (let [(items (fm/itemsOf f)) (id (textAt items ":id" ""))]
                      (if (or (stringEmpty? id) (closed? (textAt items ":status" ""))) acc (listAppend acc (pairsOf (ownsOf items) id))))))))))
        (list) (stringLines text))

fn ! owners! store: String plans: (List String) -> (List (Pair String String))
  (let [(ledger (stringTrim (optionOr (listHead (stringLines (resultOr (fileReadString (str store "/ledger.path")) ""))) "")))
        (paths (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (cons ledger plans)))]
    (fold (fn [(acc (List (Pair String String))) (p String)] -> (List (Pair String String)) (listAppend acc (planOwners (resultOr (fileReadString p) ""))))
          (storeOwners! store) paths))

; (:m :ref AUD-RUN-DEDUPE :do "pairs (row id, owner id) for each file of the queued findings an open owner already holds; an owner with the row's own id is left to the import, which skips ids already in the store")
fn heldBy tag: String fs: (List Finding) owned: (List (Pair String String)) -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (f Finding)] -> (List (Pair String String))
          (let [(id (unitId tag f.file))]
            (if (listAny? (fn [(h (Pair String String))] -> Bool (= (pairFirst h) id)) acc) acc
              (match (listFind (fn [(o (Pair String String))] -> Bool (and (= (pairFirst o) f.file) (!= (pairSecond o) id))) owned)
                ((none) acc)
                ((some o) (listAppend acc (list (pair id (pairSecond o)))))))))
        (list) fs)

fn ! git! dir: String args: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list "git" "-C" dir) args) dir (fr/childEnv (list))) (fr/limits 120 8))

fn scoped? path: String -> Bool
  (and (stringEndsWith? path ".asl")
       (and (startsAny? path (list "asl/packages/" "asl/tools/"))
            (not (or (stringEndsWith? path "Test.asl") (containsAny? (str "/" path) (list "/tests/" "/fixtures/" "/corpus/" "/examples/"))))))

; (:m :do "SINCE..HEAD changed asl files under asl/packages and asl/tools, tests and fixtures excluded, deleted files dropped; SINCE empty means the last v* tag reachable from HEAD")
fn ! rangeFiles! repo: String since: String -> (Result (Pair String (List String)) String)
  (let [(tag (if (stringEmpty? since) (stringTrim (git! repo (list "describe" "--tags" "--abbrev=0" "--match" "v*" "HEAD")).out) since))]
    (if (stringEmpty? tag) (err "no v* release tag reachable from HEAD; set :since in ~/.asl/audit.asn or pass --since")
      (let [(d (git! repo (list "diff" "--name-only" (str tag "..HEAD"))))]
        (if (!= d.exit 0) (err (str "git diff " tag "..HEAD exit " (stringFromInt64 d.exit)))
          (ok (pair tag (filter (fn [(p String)] -> Bool (and (scoped? p) (fileExists? (str repo "/" p)))) (stringLines d.out))))))))

fn ! expand path: String version: String -> String
  (let [(home (optionOr (envGet "HOME") "/tmp"))
        (p (if (stringStartsWith? path "~/") (str home (optionOr (stringSlice path 1 (stringLength path)) "")) path))]
    (stringReplace p "<version>" version))

fn numbered fs: (List Finding) -> (List Finding)
  (listReverse (pairSecond (fold (fn [(acc (Pair (List (Pair String Int64)) (List Finding))) (f Finding)] -> (Pair (List (Pair String Int64)) (List Finding))
                                   (let [(counts (pairFirst acc))
                                         (k (+ 1 (optionOr (match (listFind (fn [(c (Pair String Int64))] -> Bool (= (pairFirst c) f.lens)) counts) ((some c) (some (pairSecond c))) ((none) (none))) 0)))
                                         (counts2 (cons (pair f.lens k) (filter (fn [(c (Pair String Int64))] -> Bool (!= (pairFirst c) f.lens)) counts)))
                                         (pad (stringFromInt64 k))
                                         (id (str f.lens "-" (stringRepeat "0" (if (< (stringLength pad) 4) (- 4 (stringLength pad)) 0)) pad))]
                                     (pair counts2 (cons (with f :id id) (pairSecond acc)))))
                                 (pair (list) (list)) fs)))

fn findingRow f: Finding flagged: Bool votes: String -> String
  (str "(:finding :id " f.id " :lens " f.lens " :file " (fm/asnQuote f.file) " :line " (stringFromInt64 f.line) " :symbol " (fm/asnQuote f.symbol)
       " :severity " f.severity " :claim " (fm/asnQuote f.claim) " :evidence " (fm/asnQuote f.evidence) " :votes " votes " :flagged " (if flagged "true" "false") ")")

fn importText r: (Result pi/Report String) -> String
  (match r ((ok rep) (pi/report rep)) ((err e) (str "(:import :error " (fm/asnQuote e) ")")))

; (:m :do "run! CFG REPO SINCE DRY CALL: scan, vote, rows, dry import, then the real import unless DRY or the dry one reported bad rows; writes findings.asn, rows.asn and appends the summary to summary.asn under the run dir")
fn ! run! cfg: AuditCfg repo: String since: String dry: Bool call: (fn ! [String String] -> (Result String String)) -> (Result RunOut String)
  (match (rangeFiles! repo (if (stringEmpty? since) cfg.since since))
    ((err e) (err e))
    ((ok rf)
      (let [(tag (pairFirst rf)) (files (pairSecond rf))
            (head (stringTrim (git! repo (list "rev-parse" "--short" "HEAD")).out))
            (out (expand cfg.out (str (idPart tag) "-" head)))
            (_ (dirCreate out))
            (on (map (fn [(l Lens)] -> String l.name) cfg.lenses))
            (texts (map (fn [(p String)] -> (Pair String String) (pair p (resultOr (fileReadString (str repo "/" p)) ""))) files))
            (found (numbered (fold (fn [(acc (List Finding)) (t (Pair String String))] -> (List Finding) (listAppend acc (scanText (pairFirst t) (pairSecond t) on))) (list) texts)))
            (voted (map (fn [(f Finding)] -> (Pair Finding (List Bool))
                          (let [(l (optionOr (listFind (fn [(x Lens)] -> Bool (= x.name f.lens)) cfg.lenses) (Lens :name f.lens :queue false :models (list) :rule "any")))
                                (text (optionOr (match (listFind (fn [(t (Pair String String))] -> Bool (= (pairFirst t) f.file)) texts) ((some t) (some (pairSecond t))) ((none) (none))) ""))
                                (p (promptOf f text cfg.slice))]
                            (pair f (map (fn [(m String)] -> Bool (match (call m p) ((ok reply) (real? reply)) ((err _) false))) l.models))))
                        found))
            (isFlagged (fn [(fv (Pair Finding (List Bool)))] -> Bool
                         (let [(f (pairFirst fv))] (match (listFind (fn [(x Lens)] -> Bool (= x.name f.lens)) cfg.lenses) ((some l) (flagged? l (pairSecond fv))) ((none) false)))))
            (flaggedFs (map pairFirst (filter isFlagged voted)))
            (queued (filter (fn [(f Finding)] -> Bool (listAny? (fn [(l Lens)] -> Bool (and l.queue (= l.name f.lens))) cfg.lenses)) flaggedFs))
            (store (expand cfg.store ""))
            (held (heldBy tag queued (owners! store (map (fn [(p String)] -> String (expand p "")) cfg.plans))))
            (rows (rowsFor tag head (filter (fn [(f Finding)] -> Bool (not (listAny? (fn [(h (Pair String String))] -> Bool (= (pairFirst h) (unitId tag f.file))) held))) queued)))
            (_ (fileWrite (str out "/findings.asn") (stringJoin (map (fn [(fv (Pair Finding (List Bool)))] -> String
                                                                      (findingRow (pairFirst fv) (isFlagged fv) (str "(" (stringJoin (map (fn [(v Bool)] -> String (if v "true" "false")) (pairSecond fv)) " ") ")")))
                                                                    voted) "\n")))
            (_ (fileWrite (str out "/rows.asn") (if (stringEmpty? rows) "" (str rows "\n"))))
            (dryRep (pi/plan! rows store head true))
            (clean (match dryRep ((ok rep) (listEmpty? rep.bad)) ((err _) false)))
            (realRep (if (or dry (or (not clean) (stringEmpty? rows))) (none) (some (pi/plan! rows store head false))))
            (summary (str "(:auditRun :range " (fm/asnQuote (str tag ".." head)) " :files " (stringFromInt64 (listLength files)) " :findings " (stringFromInt64 (listLength found))
                          " :flagged " (stringFromInt64 (listLength flaggedFs)) " :queued " (stringFromInt64 (listLength queued))
                          " :rows " (stringFromInt64 (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:u ")) (stringLines rows))))
                          " :dedup (" (stringJoin (map (fn [(h (Pair String String))] -> String (str "(" (fm/asnQuote (pairFirst h)) " " (fm/asnQuote (pairSecond h)) ")")) held) " ") ")"
                          " :dry " (importText dryRep) " :import " (match realRep ((some r) (importText r)) ((none) (if dry "skipped" "none"))) " :out " (fm/asnQuote out) ")"))
            (_ (fileAppend (str out "/summary.asn") (str summary "\n")))]
        (ok (RunOut :summary summary :rows rows :findings found :flagged flaggedFs)))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (envGet "HOME") "/tmp"))
        (cfgPath (st/opt args "config" (str home "/.asl/audit.asn")))
        (repo (st/opt args "repo" "."))
        (since (st/opt args "since" ""))
        (dry (listContains? args "--dry"))
        (cmd (optionOr (listHead args) ""))]
    (if (not (or (= cmd "run") (= cmd "check")))
      (do (eprintln "usage: audit run|check [--config FILE] [--repo DIR] [--since REF] [--dry]") (ok 2))
      (match (match (fileReadString cfgPath) ((err e) (err (str cfgPath ": " e))) ((ok t) (parseConfig t)))
        ((err e) (do (eprintln e) (ok 1)))
        ((ok cfg)
          (if (= cmd "check") (do (println (str "(:auditConfig :ok true :lenses " (st/qList (map (fn [(l Lens)] -> String l.name) cfg.lenses)) ")")) (ok 0))
            (match (run! cfg repo since dry (rs/callModelFor! repo (str home "/.asl/run/usage/auditCalls.asn") (list)))
              ((err e) (do (eprintln e) (ok 1)))
              ((ok r) (do (println r.summary) (ok 0)))))))))
