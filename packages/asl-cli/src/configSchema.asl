(module asl-cli/configSchema
  :x [Rule Issue Checked rulesOf checkText checkFile! receipt cli! warnText! warnLines! warnIn! defaultOf keyCount groupsOf]
  :i [(asl-parser/reader :a rd)])

; (:m :ref WS-CONFIG-SCHEMA :do "asl/grammar/workspaceConfig.asn holds one row per key of a strict config group; this module is the generic checker over those rows, so a new key is a row, not code. A group named in the rows is closed (unknown key, wrong type, out of range are errors), any other top-level group is not looked at. Runtime readers keep their documented default and call warnText! to report what the check would reject")

(schema Rule (:f grp String) (:f name String) (:f kind String) (:f lo Int64) (:f hi Int64) (:f choices (List String)) (:f dflt String))

(schema Issue (:f level String) (:f path String) (:f code String) (:f msg String))

(schema Checked (:f issues (List Issue)) (:f checked Int64))

(schema KV (:f key String) (:f val rd/SExpr))

(schema Bal (:f depth Int64) (:f inStr Bool) (:f esc Bool) (:f bad Bool))

fn balStep s: Bal c: String -> Bal
  (if s.inStr
    (cond
      (s.esc (with s :esc false))
      ((= c "\\") (with s :esc true))
      ((= c "\"") (with s :inStr false))
      (else s))
    (cond
      ((= c "\"") (with s :inStr true))
      ((or (= c "(") (= c "[")) (with s :depth (+ s.depth 1)))
      ((or (= c ")") (= c "]")) (with s :depth (- s.depth 1) :bad (or s.bad (<= s.depth 0))))
      (else s)))

fn balanced? text: String -> Bool
  (let [(s (fold balStep (Bal :depth 0 :inStr false :esc false :bad false) (stringChars text)))]
    (and (= s.depth 0) (and (not s.bad) (not s.inStr))))

fn dropComments text: String -> String
  (stringJoin (filter (fn [(l String)] -> Bool (not (stringStartsWith? (stringTrim l) ";"))) (stringSplit text "\n")) "\n")

fn formsOf text: String -> (List rd/SExpr)
  (rd/sexprToList (rd/parseSexpr (str "(" (dropComments text) "\n)")))

fn unq s: String -> String
  (if (and (stringStartsWith? s "\"") (>= (stringLength s) 2))
    (optionOr (stringSlice s 1 (- (stringLength s) 1)) "")
    s)

fn bare s: String -> String
  (if (stringStartsWith? s ":") (optionOr (stringSlice s 1 (stringLength s)) "") s)

fn wordOf v: rd/SExpr -> String
  (if (rd/isAtom? v) (bare (unq (rd/sexprHead v))) "")

fn kvs items: (List rd/SExpr) -> (List KV)
  (match (listHead items)
    ((none) (list))
    ((some h)
      (let [(rest (optionOr (listTail items) (list)))]
        (if (and (rd/isAtom? h) (stringStartsWith? (rd/sexprHead h) ":"))
          (match (listHead rest)
            ((some v) (cons (KV :key (rd/sexprHead h) :val v) (kvs (optionOr (listTail rest) (list)))))
            ((none) (list (KV :key (rd/sexprHead h) :val (rd/makeAtom "")))))
          (kvs rest)))))

fn kvGet pairs: (List KV) key: String -> (Option rd/SExpr)
  (match (listHead (filter (fn [(p KV)] -> Bool (= p.key key)) pairs))
    ((some p) (some p.val))
    ((none) (none)))

fn textOf pairs: (List KV) key: String -> String
  (match (kvGet pairs key) ((some v) (if (rd/isAtom? v) (unq (rd/sexprHead v)) "")) ((none) ""))

fn intOf pairs: (List KV) key: String fallback: Int64 -> Int64
  (match (kvGet pairs key) ((some v) (optionOr (stringToInt64 (wordOf v)) fallback)) ((none) fallback))

fn ruleOf row: rd/SExpr -> (Option Rule)
  (if (!= (rd/sexprHead row) ":cfgKey")
    (none)
    (let [(p (kvs (optionOr (listTail (rd/sexprToList row)) (list))))]
      (some (Rule :grp (textOf p ":grp") :name (textOf p ":name") :kind (textOf p ":kind")
                  :lo (intOf p ":lo" -4611686018427387904) :hi (intOf p ":hi" 4611686018427387904)
                  :choices (match (kvGet p ":choices") ((some c) (map wordOf (rd/sexprToList c))) ((none) (list)))
                  :dflt (textOf p ":default")))))

fn rulesOf schemaText: String -> (List Rule)
  (fold (fn [(acc (List Rule)) (f rd/SExpr)] -> (List Rule)
          (match (ruleOf f) ((some r) (listAppend acc (list r))) ((none) acc)))
        (list) (formsOf schemaText))

fn keyCount rules: (List Rule) -> Int64
  (listLength rules)

fn groupsOf rules: (List Rule) -> (List String)
  (fold (fn [(acc (List String)) (r Rule)] -> (List String) (if (listContains? acc r.grp) acc (listAppend acc (list r.grp)))) (list) rules)

fn findRule rules: (List Rule) grp: String name: String -> (Option Rule)
  (listHead (filter (fn [(r Rule)] -> Bool (and (= r.grp grp) (= r.name name))) rules))

fn defaultOf rules: (List Rule) grp: String name: String -> (Option String)
  (match (findRule rules grp name) ((some r) (some r.dflt)) ((none) (none)))

fn sizeOk? w: String -> Bool
  (let [(n (stringLength w))
        (unit (if (> n 0) (optionOr (stringSlice w (- n 1) n) "") ""))
        (digits (if (or (= unit "K") (or (= unit "M") (= unit "G"))) (optionOr (stringSlice w 0 (- n 1)) "") w))]
    (match (stringToInt64 digits) ((some k) (> k 0)) ((none) false)))

fn ageOk? w: String -> Bool
  (let [(n (stringLength w))
        (unit (if (> n 0) (optionOr (stringSlice w (- n 1) n) "") ""))
        (digits (if (or (= unit "m") (= unit "h")) (optionOr (stringSlice w 0 (- n 1)) "") w))]
    (match (stringToInt64 digits) ((some k) (> k 0)) ((none) false)))

fn versionOk? w: String -> Bool
  (let [(parts (stringSplit w "."))
        (n (listLength parts))]
    (and (or (= n 2) (= n 3))
         (= (listLength (filter (fn [(p String)] -> Bool (match (stringToInt64 p) ((some k) (>= k 0)) ((none) false))) parts)) n)))

fn shown v: rd/SExpr -> String
  (rd/renderSexpr v)

; (:m :ref WS-CONFIG-SCHEMA :do "a value problem is a pair of a code (badType or outOfRange) and a message, none when the value is sound")
fn valueProblem r: Rule v: rd/SExpr -> (Option (Pair String String))
  (let [(w (wordOf v))
        (got (shown v))]
    (cond
      ((= r.kind "int")
        (match (stringToInt64 w)
          ((none) (some (pair "badType" (str "must be an integer, got " got))))
          ((some n) (if (and (>= n r.lo) (<= n r.hi)) (none) (some (pair "outOfRange" (str "must be " (stringFromInt64 r.lo) ".." (stringFromInt64 r.hi) ", got " got)))))))
      ((= r.kind "bool")
        (if (or (= w "true") (= w "false")) (none) (some (pair "badType" (str "must be true or false, got " got)))))
      ((= r.kind "enum")
        (if (and (rd/isAtom? v) (listContains? r.choices w)) (none) (some (pair "outOfRange" (str "must be one of " (stringJoin r.choices " ") ", got " got)))))
      ((= r.kind "size")
        (if (and (rd/isAtom? v) (sizeOk? w)) (none) (some (pair "outOfRange" (str "must be a positive byte count with an optional K, M or G, got " got)))))
      ((= r.kind "age")
        (if (and (rd/isAtom? v) (ageOk? w)) (none) (some (pair "outOfRange" (str "must be a positive age in minutes with an optional m or h, got " got)))))
      ((= r.kind "version")
        (if (and (rd/isAtom? v) (versionOk? w)) (none) (some (pair "badType" (str "must be a version N.N or N.N.N, got " got)))))
      ((or (= r.kind "path") (= r.kind "string"))
        (if (and (rd/isAtom? v) (not (stringEmpty? w))) (none) (some (pair "badType" (str "must be a non-empty string, got " got)))))
      ((= r.kind "strList")
        (if (and (or (rd/isList? v) (rd/isVect? v))
                 (= (listLength (filter (fn [(e rd/SExpr)] -> Bool (and (rd/isAtom? e) (not (stringEmpty? (wordOf e))))) (rd/sexprToList v))) (listLength (rd/sexprToList v))))
          (none)
          (some (pair "badType" (str "must be a list of non-empty strings, got " got)))))
      (else (some (pair "badRule" (str "the schema row for " r.name " has the unknown kind " r.kind))))))

fn kvIssues rules: (List Rule) grp: String kv: KV seen: (List String) -> (List Issue)
  (let [(name (bare kv.key))
        (path (str ":" grp " " kv.key))]
    (cond
      ((listContains? seen kv.key) (list (Issue :level "error" :path path :code "duplicateKey" :msg (str "key " kv.key " appears twice in :" grp))))
      (else
        (match (findRule rules grp name)
          ((none) (list (Issue :level "error" :path path :code "unknownKey"
                               :msg (str "unknown key " kv.key " in :" grp "; known: " (stringJoin (map (fn [(r Rule)] -> String (str ":" r.name)) (filter (fn [(r Rule)] -> Bool (= r.grp grp)) rules)) " ")))))
          ((some r) (match (valueProblem r kv.val)
                      ((none) (list))
                      ((some pr) (list (Issue :level "error" :path path :code (pairFirst pr) :msg (str "key " kv.key " " (pairSecond pr) "; the reader keeps the default " r.dflt))))))))))

fn groupIssues rules: (List Rule) grp: String v: rd/SExpr -> (Checked)
  (if (not (or (rd/isList? v) (rd/isVect? v)))
    (Checked :issues (list (Issue :level "error" :path (str ":" grp) :code "badType" :msg (str "group :" grp " must be a list of key value pairs, got " (shown v)))) :checked 0)
    (let [(pairs (kvs (rd/sexprToList v)))
          (walked (fold (fn [(acc (Pair (List String) (List Issue))) (kv KV)] -> (Pair (List String) (List Issue))
                          (pair (listAppend (pairFirst acc) (list kv.key)) (listAppend (pairSecond acc) (kvIssues rules grp kv (pairFirst acc)))))
                        (pair (list) (list)) pairs))]
      (Checked :issues (pairSecond walked) :checked (listLength pairs))))

fn checkText text: String rules: (List Rule) -> Checked
  (if (not (balanced? text))
    (Checked :issues (list (Issue :level "error" :path "" :code "unbalanced" :msg "the file has unbalanced delimiters")) :checked 0)
    (match (listHead (formsOf text))
      ((none) (Checked :issues (list (Issue :level "error" :path "" :code "empty" :msg "the file holds no form")) :checked 0))
      ((some top)
        (let [(groups (groupsOf rules))
              (top1 (kvs (optionOr (listTail (rd/sexprToList top)) (list))))]
          (fold (fn [(acc Checked) (kv KV)] -> Checked
                  (if (listContains? groups (bare kv.key))
                    (let [(g (groupIssues rules (bare kv.key) kv.val))]
                      (Checked :issues (listAppend acc.issues g.issues) :checked (+ acc.checked g.checked)))
                    acc))
                (Checked :issues (list) :checked 0) top1)))))

fn quoted s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn issueAsn i: Issue -> String
  (str "(:issue :path " (quoted i.path) " :code " i.code " :msg " (quoted i.msg) ")")

fn receipt file: String c: Checked -> String
  (let [(errs (filter (fn [(i Issue)] -> Bool (= i.level "error")) c.issues))
        (warns (filter (fn [(i Issue)] -> Bool (= i.level "warn")) c.issues))]
    (str "(:workspaceConfigCheck :file " (quoted file) " :status :" (if (listEmpty? errs) "ok" "error")
         " :checked " (stringFromInt64 c.checked)
         " :errors (" (stringJoin (map issueAsn errs) " ") ") :warnings (" (stringJoin (map issueAsn warns) " ") "))"))

fn ! checkFile! file: String schemaPath: String -> (Result Checked String)
  (match (fileReadString schemaPath)
    ((err e) (err (str "cannot read the schema " schemaPath ": " e)))
    ((ok schemaText)
      (match (fileReadString file)
        ((err e) (err (str "cannot read " file ": " e)))
        ((ok text) (ok (checkText text (rulesOf schemaText))))))) 

; (:m :ref WS-CONFIG-SCHEMA :do "the runtime side of the check: a reader that has loaded config text calls this with the root holding asl/grammar/workspaceConfig.asn; every error of the check is one stderr line, the caller keeps its documented default. A root without the schema file says nothing")
fn ! warnLines! root: String file: String text: String -> (List String)
  (match (fileReadString (str root "/asl/grammar/workspaceConfig.asn"))
    ((err _) (list))
    ((ok schemaText)
      (map (fn [(i Issue)] -> String (str "asl: config " file " " i.path ": " i.msg))
           (filter (fn [(i Issue)] -> Bool (= i.level "error")) (checkText text (rulesOf schemaText)).issues))))

fn ! warnText! root: String file: String text: String -> Unit
  (let [(_ (map (fn [(l String)] -> Unit (eprintln l)) (warnLines! root file text)))]
    ())

fn parentOfDir dir: String -> String
  (let [(parts (stringSplit dir "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn ! nearestConfigPath! dir: String -> String
  (let [(cfg (str dir "/.asl.config.asn"))]
    (cond
      ((fileExists? cfg) cfg)
      ((or (stringEmpty? dir) (= dir "/")) "")
      (else (nearestConfigPath! (parentOfDir dir)))))

; (:m :ref WS-CONFIG-SCHEMA :do "warnIn!: the nearest .asl.config.asn above dir and ~/.asl/config.asn, each checked and each error on stderr; the one call a reader makes where it loads config, the reader itself keeps its default")
fn ! warnIn! root: String dir: String -> Unit
  (let [(near (nearestConfigPath! dir))
        (home (str (optionOr (envGet "HOME") "") "/.asl/config.asn"))
        (_ (if (stringEmpty? near) () (warnText! root near (resultOr (fileReadString near) ""))))
        (_ (if (fileExists? home) (warnText! root home (resultOr (fileReadString home) "")) ()))]
    ())

fn ! cli! args: (List String) -> (Result Int64 String)
  (let [(rest (if (= (optionOr (listHead args) "") "check") (optionOr (listTail args) (list)) args))
        (file (optionOr (listHead rest) ""))
        (root (resultOr (realPath ".") "."))
        (schemaPath (match (listGet rest 1) ((some p) p) ((none) (str root "/asl/grammar/workspaceConfig.asn"))))]
    (if (stringEmpty? file)
      (err "usage: workspaceConfigCheck check FILE [SCHEMA]")
      (match (checkFile! file schemaPath)
        ((err e) (err e))
        ((ok c) (let [(_ (fdWrite 1 (str (receipt file c) "\n")))]
                  (ok (if (listEmpty? (filter (fn [(i Issue)] -> Bool (= i.level "error")) c.issues)) 0 1)))))))
