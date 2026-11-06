(module asl-gates/vcsDirectAudit
  :x [cacheText scanFilesC parseCache scanCached! auditWith! cacheDirFor! storeRoot viewKey namesDigest cap Site Verdict Helpers scanSource scanFiles helpersOf verdictOf allowKeys parseAllow siteKey receiptOf receiptWith grownOf audit! auditAt! trackedAsl! emitRows main vcsVerbs excluded? decodeString segmentsOf verbState]
  :i [(asl-parser/lexer :a lex) (asl-gates/suiteRunner :a sr)])

; (:m :ref VCS-DIRECT-GIT-AUDIT :do "finds literal git argv outside asl/tools/vcs: a (list, (cons or (listAppend (list form that starts with the string git, a (str form or a string whose shell segment starts with git, and a call of a git helper, whose first non-option word is commit, add, update-ref, commit-tree, push, reset or checkout; a git helper is named git*! (or gitIn gitOut gitRun gitCmd) or, by data, is a fn whose body builds a git argv or git string whose verb is a value, or passes values on to another helper, iterated to a fixpoint; each site is keyed path#symbol plus the verb, never a line, and counts its occurrences; the allowlist .asl/mem/vcsDirectAllow.asn only shrinks: a new or extra site is a violation, a row without its sites is a violation, and a product row grown since the base (default the merge base with main) is a violation; comments and strings that merely contain git text are not sites; asl run asl/packages/asl-gates/src/vcsDirectAudit.asl [--root DIR] [--allow FILE] [--base REF] [--emit] [--helpers] prints one ASN receipt, exit 0 clean, 1 violation, 2 error")
(schema Site
  (:f file String)
  (:f symbol String)
  (:f verb String))

(schema Verdict
  (:f found (List Site))
  (:f newSites (List String))
  (:f stale (List String)))

(schema Coll
  (:f kind String)
  (:f at Int64)
  (:f items (List String))
  (:f opaque Int64))

(schema Helpers
  (:f local (List String))
  (:f names (List String)))

(schema Scan
  (:f symbol String)
  (:f prev (List String))
  (:f depth Int64)
  (:f colls (List Coll))
  (:f sites (List Site))
  (:f found (List String))
  (:f params (List String))
  (:f inSig Bool))

fn vcsVerbs -> (List String)
  (list "commit" "add" "update-ref" "commit-tree" "push" "reset" "checkout")

fn valueOptions -> (List String)
  (list "-C" "-c" "--git-dir" "--work-tree" "--namespace" "--super-prefix" "--config-env")

fn transparentHeads -> (List String)
  (list "list" "cons" "listAppend" "listConcat")

fn placeholder -> String
  "%%v%%"

fn paramMark -> String
  "%%p%%"

fn mark? x: String -> Bool
  (or (= x (placeholder)) (= x (paramMark)))

fn excluded? path: String -> Bool
  (stringStartsWith? path "asl/tools/vcs/")

fn decodeStep acc: (Pair Bool (List String)) ch: String -> (Pair Bool (List String))
  (if (pairFirst acc)
    (pair false (cons (cond ((= ch "n") "\n") ((= ch "t") "\t") ((= ch "r") "\r") (else ch)) (pairSecond acc)))
    (if (= ch "\\") (pair true (pairSecond acc)) (pair false (cons ch (pairSecond acc)))))

; (:m :do "the text of a string token: outer quotes dropped and the escapes n t r backslash and quote decoded, so an escaped newline splits a shell string like a real one")
fn decodeString raw: String -> String
  (let [(inner (if (and (stringStartsWith? raw "\"") (>= (stringLength raw) 2))
                 (optionOr (stringSlice raw 1 (- (stringLength raw) 1)) "")
                 raw))]
    (stringJoin (listReverse (pairSecond (fold decodeStep (pair false (list)) (stringChars inner)))) ""))

fn baseName name: String -> String
  (optionOr (listLast (stringSplit name "/")) name)

fn gitHelper? name: String -> Bool
  (let [(b (baseName name))]
    (and (stringStartsWith? b "git")
         (or (stringEndsWith? b "!") (listContains? (list "gitIn" "gitOut" "gitRun" "gitCmd") b))))

; (:m :do "a command word is git when its last path segment is git, so /usr/bin/git and any .../git count")
fn gitWord? w: String -> Bool
  (= (baseName w) "git")

fn helper? h: Helpers file: String name: String -> Bool
  (or (gitHelper? name)
      (if (stringContains? name "/")
        (listContains? h.names (baseName name))
        (listContains? h.local name)))

fn stripWord w: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace w "\"" "") "'" "") "(" "") ")" "") "`" "")

; (:m :do "the shell words of a text: split at blanks, quotes and subshell parens dropped")
fn wordsOf text: String -> (List String)
  (filter (fn [(w String)] -> Bool (not (stringEmpty? w)))
          (map stripWord (stringSplit (stringReplace (stringReplace (stringReplace text "\t" " ") "\n" " ") "\r" " ") " ")))

fn shellLead? w: String -> Bool
  (or (listContains? (list "then" "else" "do" "if" "elif" "while" "until" "time" "!" "{" "}" "env" "exec" "command" "nohup" "xargs" "sudo" "eval") w)
      (and (stringContains? w "=") (not (or (stringStartsWith? w "-") (stringStartsWith? w "=")))))

; (:m :ref VCS-AUDIT-ENV-OPTS :do "the options env takes before its command: -u NAME, --unset NAME, -C DIR, --chdir DIR and -S STRING skip their value, any other word that starts with a dash (-i, -0, --ignore-environment, -uNAME) is skipped alone; NAME=v words are skipped by shellLead? afterwards")
fn envOptions ws: (List String) -> (List String)
  (match (listHead ws)
    ((none) ws)
    ((some w)
      (cond
        ((listContains? (list "-u" "--unset" "-C" "--chdir" "-S") w) (envOptions (listDrop ws 2)))
        ((and (stringStartsWith? w "-") (> (stringLength w) 1)) (envOptions (listDrop ws 1)))
        (else ws))))

; (:m :do "a segment's command word: leading shell keywords (then else do if elif while until time ! { }), the prefixes env exec command nohup xargs sudo eval and VAR=x assignments are not the command")
fn dropLead ws: (List String) -> (List String)
  (match (listHead ws)
    ((none) ws)
    ((some w) (cond ((= w "env") (dropLead (envOptions (listDrop ws 1)))) ((shellLead? w) (dropLead (listDrop ws 1))) (else ws))))

; (:m :do "the command segments of a shell text, split at && || ; & newlines, $( and backquotes and a pipe with a blank on either side (a#f|git key is one word), each as its words")
fn segmentsOf text: String -> (List (List String))
  (let [(flat (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace text "$(" ";") "`" ";") "||" ";") "&&" ";") " |" ";") "| " ";") "&" ";") "\n" ";") "\r" ";"))]
    (filter (fn [(ws (List String))] -> Bool (not (listEmpty? ws))) (map (fn [(seg String)] -> (List String) (dropLead (wordsOf seg))) (stringSplit flat ";"))))

fn option? s: String -> Bool
  (or (stringStartsWith? s "-") (stringContains? s "="))

fn pathLike? s: String -> Bool
  (or (stringContains? s "/") (stringStartsWith? s "."))

fn verbLoop xs: (List String) skipPh: Bool skipNext: Bool seenPh: Bool -> String
  (match (listHead xs)
    ((none) (if seenPh "param" "none"))
    ((some x)
      (let [(rest (listDrop xs 1))]
        (cond
          (skipNext (verbLoop rest skipPh false seenPh))
          ((listContains? (valueOptions) x) (verbLoop rest skipPh true seenPh))
          ((mark? x) (cond (skipPh (verbLoop rest skipPh false (or seenPh (= x (paramMark))))) ((= x (paramMark)) "param") (else "none")))
          ((option? x) (verbLoop rest skipPh false seenPh))
          ((and skipPh (pathLike? x)) (verbLoop rest skipPh false seenPh))
          ((listContains? (vcsVerbs) x) (str "v:" x))
          (else "word")))))

; (:m :do "what the words after git name: v:VERB for a covered verb, word for any other verb, param when the verb comes from a value (the fn is a helper), none when nothing follows; the value of -C, -c and the other valued global options is never the verb; skipPh is true for a helper call, whose leading values and path literals are its own arguments")
fn verbState items: (List String) skipPh: Bool -> String
  (verbLoop (if (gitWord? (optionOr (listHead items) "")) (listDrop items 1) items) skipPh false false)

fn segmentStates text: String -> (List String)
  (map (fn [(ws (List String))] -> String (verbState ws false))
       (filter (fn [(ws (List String))] -> Bool (gitWord? (optionOr (listHead ws) ""))) (segmentsOf text)))

fn verbsIn states: (List String) -> (List String)
  (map (fn [(s String)] -> String (optionOr (stringSlice s 2 (stringLength s)) ""))
       (filter (fn [(s String)] -> Bool (stringStartsWith? s "v:")) states))

fn addSite scan: Scan file: String verb: String -> Scan
  (with scan :sites (cons (Site :file file :symbol scan.symbol :verb verb) scan.sites))

fn addSites scan: Scan file: String verbs: (List String) -> Scan
  (fold (fn [(acc Scan) (v String)] -> Scan (addSite acc file v)) scan verbs)

fn markHelper scan: Scan file: String -> Scan
  (if (or (= scan.symbol "<top>") (= scan.symbol "<fn>"))
    scan
    (with scan :found (cons (str file "|" scan.symbol) scan.found)))

; (:m :do "a helper call passes its argv through, making its fn a helper too, only when it has no verb word, at least two values and a parameter after the first value, as in (git dir args); a single value is a directory or a handle")
fn helperState items: (List String) -> String
  (let [(st (verbState items true))]
    (if (and (= st "param") (not (listContains? (listDrop (filter mark? items) 1) (paramMark)))) "none" st))

fn collStates c: Coll -> (List String)
  (let [(items (listReverse c.items))]
    (cond
      ((= c.kind "str") (segmentStates (stringJoin items "")))
      ((= c.kind "helper") (list (helperState items)))
      (else (list (verbState items false)))))

fn finishColl scan: Scan file: String c: Coll -> Scan
  (let [(states (collStates c))
        (withSites (addSites scan file (verbsIn states)))]
    (if (listContains? states "param") (markHelper withSites file) withSites))

fn pushPrev scan: Scan text: String -> (List String)
  (listTake (cons text scan.prev) 4)

fn prevAt scan: Scan i: Int64 -> String
  (optionOr (listGet scan.prev i) "")

fn addItem c: Coll item: String -> Coll
  (with c :items (cons item c.items))

fn itemsOfText c: Coll text: String -> Coll
  (if (= c.kind "str")
    (addItem c text)
    (fold addItem c (wordsOf text)))

fn markFor c: Coll m: String -> String
  (if (= c.kind "str") (str " " m " ") m)

fn placeholderFor c: Coll -> String
  (markFor c (placeholder))

fn closedScan s: Scan colls: (List Coll) d: Int64 prev: (List String) -> Scan
  (with s :colls colls :depth d :prev prev)

fn setOpaque c: Coll d: Int64 -> Coll
  (with c :opaque d)

fn onClose file: String scan: Scan -> Scan
  (let [(d scan.depth)
        (done (filter (fn [(c Coll)] -> Bool (= c.at d)) scan.colls))
        (left (map (fn [(c Coll)] -> Coll (if (= c.opaque d) (with c :opaque 0) c))
                   (filter (fn [(c Coll)] -> Bool (!= c.at d)) scan.colls)))
        (finished (fold (fn [(acc Scan) (c Coll)] -> Scan (finishColl acc file c)) scan done))]
    (closedScan finished left (- d 1) (pushPrev scan ")")))

fn nestIn c: Coll d: Int64 head: String -> Coll
  (cond
    ((or (!= c.opaque 0) (>= c.at d)) c)
    ((and (!= c.kind "str") (listContains? (transparentHeads) head)) c)
    (else (setOpaque (addItem c (placeholderFor c)) d)))

fn onHead file: String h: Helpers scan: Scan head: String -> Scan
  (let [(d scan.depth)
        (nested (map (fn [(c Coll)] -> Coll (nestIn c d head)) scan.colls))
        (opened (cond
                  ((= head "str") (cons (Coll :kind "str" :at d :items (list) :opaque 0) nested))
                  ((helper? h file head) (cons (Coll :kind "helper" :at d :items (list "git") :opaque 0) nested))
                  (else nested)))]
    (with scan :colls opened :prev (pushPrev scan head)))

fn onString file: String scan: Scan text: String -> Scan
  (let [(live (listAny? (fn [(c Coll)] -> Bool (= c.opaque 0)) scan.colls))
        (fed (map (fn [(c Coll)] -> Coll (if (= c.opaque 0) (itemsOfText c text) c)) scan.colls))
        (argvOpen (and (gitWord? text) (and (= (prevAt scan 1) "(") (listContains? (list "list" "cons") (prevAt scan 0)))))
        (appendOpen (and argvOpen (and (= (prevAt scan 3) "(") (listContains? (list "listAppend" "listConcat") (prevAt scan 2)))))
        (colls (if argvOpen
                 (cons (Coll :kind "argv" :at (if appendOpen (- scan.depth 1) scan.depth) :items (list "git") :opaque 0) fed)
                 fed))
        (base (with scan :colls colls :prev (pushPrev scan text)))]
    (if (or live argvOpen) base (addSites base file (verbsIn (segmentStates text)))))

fn atomMark scan: Scan text: String -> String
  (if (listContains? scan.params (optionOr (listHead (stringSplit text ".")) text)) (paramMark) (placeholder))

fn onAtom scan: Scan text: String -> Scan
  (with scan :colls (map (fn [(c Coll)] -> Coll (if (= c.opaque 0) (addItem c (markFor c (atomMark scan text))) c)) scan.colls)
             :prev (pushPrev scan text))

fn paramName sym: String -> String
  (if (stringEndsWith? sym ":") (optionOr (stringSlice sym 0 (- (stringLength sym) 1)) sym) sym)

; (:m :do "the fn a token belongs to and the names in its signature, read from fn at column 1 up to the arrow")
fn symbolAfter scan: Scan isSym: Bool sym: String col: Int64 -> Scan
  (cond
    ((and isSym (and (<= col 1) (= sym "fn"))) (with scan :symbol "<fn>" :params (list) :inSig false))
    ((and isSym (= scan.symbol "<fn>")) (if (= sym "!") scan (with scan :symbol sym :inSig true)))
    ((and isSym scan.inSig) (if (= sym "->") (with scan :inSig false) (with scan :params (cons (paramName sym) scan.params))))
    (else scan))

fn step file: String h: Helpers scan0: Scan tok: lex/Token -> Scan
  (let [(sym (match tok.kind ((lex/tokSymbol n) n) (_ "")))
        (isSym (match tok.kind ((lex/tokSymbol _) true) (_ false)))
        (scan (symbolAfter scan0 isSym sym tok.col))]
    (stepKind file h scan tok))

fn stepKind file: String h: Helpers scan: Scan tok: lex/Token -> Scan
    (match tok.kind
      ((lex/tokLparen) (with scan :depth (+ scan.depth 1) :prev (pushPrev scan "(")))
      ((lex/tokLbracket) (with scan :depth (+ scan.depth 1) :prev (pushPrev scan "(")))
      ((lex/tokRparen) (onClose file scan))
      ((lex/tokRbracket) (onClose file scan))
      ((lex/tokString v) (onString file scan (decodeString v)))
      ((lex/tokSymbol n) (if (= (prevAt scan 0) "(") (onHead file h scan n) (onAtom scan n)))
      ((lex/tokInt _) (onAtom scan tok.rawText))
      ((lex/tokFloat _) (onAtom scan tok.rawText))
      (_ (with scan :prev (pushPrev scan tok.rawText))))

fn scanToks h: Helpers file: String toks: (List lex/Token) -> Scan
  (fold (fn [(acc Scan) (t lex/Token)] -> Scan (step file h acc t))
        (Scan :symbol "<top>" :prev (list) :depth 0 :colls (list) :sites (list) :found (list) :params (list) :inSig false)
        toks)

fn unique xs: (List String) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (cons x acc))) (list) xs))

fn keyName k: String -> String
  (optionOr (listLast (stringSplit k "|")) k)

fn helpersFrom keys: (List String) -> Helpers
  (Helpers :local keys :names (unique (map keyName keys)))

; (:m :do "the helper view one file is scanned with: its own helper names unqualified, every helper name for a qualified call")
fn helpersFor h: Helpers file: String -> Helpers
  (Helpers :local (map keyName (filter (fn [(k String)] -> Bool (stringStartsWith? k (str file "|"))) h.local)) :names h.names)

fn helperLoop files: (List (Pair String (List lex/Token))) h: Helpers rounds: Int64 -> Helpers
  (let [(found (unique (listAppend h.local (listFlatMap (fn [(f (Pair String (List lex/Token)))] -> (List String) (scanToks (helpersFor h (pairFirst f)) (pairFirst f) (pairSecond f)).found) files))))]
    (if (or (<= rounds 0) (= (listLength found) (listLength h.local)))
      (helpersFrom found)
      (helperLoop files (helpersFrom found) (- rounds 1))))

; (:m :do "the git helpers of a tree by data: the files that hold the text git, outside the vcs layer, are tokenized once and rescanned until no fn joins the set, at most 8 rounds")
fn helpersOf files: (List (Pair String String)) -> Helpers
  (helperLoop (map (fn [(f (Pair String String))] -> (Pair String (List lex/Token)) (pair (pairFirst f) (lex/tokenize (pairSecond f))))
                   (filter (fn [(f (Pair String String))] -> Bool (and (not (excluded? (pairFirst f))) (stringContains? (pairSecond f) "git"))) files))
              (Helpers :local (list) :names (list)) 8)

fn sitesWith h: Helpers file: String source: String -> (List Site)
  (if (excluded? file) (list) (listReverse (scanToks (helpersFor h file) file (lex/tokenize source)).sites))

; (:m :do "the sites of one source text in source order, empty for a file under asl/tools/vcs")
fn scanSource file: String source: String -> (List Site)
  (sitesWith (helpersOf (list (pair file source))) file source)

fn scanFiles files: (List (Pair String String)) -> (List Site)
  (let [(h (helpersOf files))]
    (listFlatMap (fn [(f (Pair String String))] -> (List Site) (sitesWith h (pairFirst f) (pairSecond f))) files))

fn siteKey s: Site -> String
  (str s.file "#" s.symbol "|git " s.verb)

fn removeOne xs: (List String) x: String -> (List String)
  (match (listIndexOf xs x)
    ((none) xs)
    ((some i) (listAppend (listTake xs i) (listDrop xs (+ i 1)))))

fn excessStep acc: (Pair (List String) (List String)) x: String -> (Pair (List String) (List String))
  (if (listContains? (pairSecond acc) x)
    (pair (pairFirst acc) (removeOne (pairSecond acc) x))
    (pair (cons x (pairFirst acc)) (pairSecond acc)))

; (:m :do "multiset difference: every x of xs beyond its count in ys, in order")
fn excess xs: (List String) ys: (List String) -> (List String)
  (listReverse (pairFirst (fold excessStep (pair (list) ys) xs)))

fn repeatKey key: String n: Int64 -> (List String)
  (if (<= n 0) (list) (cons key (repeatKey key (- n 1))))

fn rowField r: (List String) i: Int64 -> String
  (optionOr (listGet r i) "")

fn flushRow r: (List String) acc: (List String) -> (List String)
  (let [(site (rowField r 1))
        (argv (rowField r 2))
        (n (optionOr (stringToInt64 (rowField r 3)) 1))]
    (if (or (stringEmpty? site) (stringEmpty? argv)) acc (listAppend acc (repeatKey (str site "|" argv) (max n 1)))))

; (:m :do "a row under parse is (field site argv n): the last keyword, the :site and :argv strings and the :n count")
fn allowStep acc: (Pair (List String) (List String)) t: lex/Token -> (Pair (List String) (List String))
  (let [(r (pairFirst acc))
        (field (rowField r 0))]
    (match t.kind
      ((lex/tokKeyword k) (if (= k ":site")
                            (pair (list ":site" "" "" "1") (flushRow r (pairSecond acc)))
                            (pair (list k (rowField r 1) (rowField r 2) (rowField r 3)) (pairSecond acc))))
      ((lex/tokString v) (cond
                           ((= field ":site") (pair (list "" (decodeString v) (rowField r 2) (rowField r 3)) (pairSecond acc)))
                           ((= field ":argv") (pair (list "" (rowField r 1) (decodeString v) (rowField r 3)) (pairSecond acc)))
                           (else acc)))
      ((lex/tokInt i) (if (= field ":n") (pair (list "" (rowField r 1) (rowField r 2) (stringFromInt64 i)) (pairSecond acc)) acc))
      (_ acc)))

; (:m :do "the site keys of an allowlist text: each (:site S ... :argv A [:n N]) row gives the key S|A, repeated N times (default 1), in order")
fn parseAllow text: String -> (List String)
  (let [(state (fold allowStep (pair (list "" "" "" "1") (list)) (lex/tokenize text)))]
    (flushRow (pairFirst state) (pairSecond state)))

fn allowKeys text: String -> (List String)
  (parseAllow text)

fn verdictOf sites: (List Site) allow: (List String) -> Verdict
  (let [(keys (map siteKey sites))]
    (Verdict :found sites :newSites (excess keys allow) :stale (excess allow keys)))

fn fixture? key: String -> Bool
  (let [(path (optionOr (listHead (stringSplit key "#")) ""))]
    (or (stringStartsWith? path "tests/") (stringContains? path "/tests/")))

; (:m :do "allowlist keys present now beyond their count at the base: product keys (first) are a violation, keys under a tests directory (second) are reported only, since fixtures need real repos")
fn grownOf allow: (List String) baseAllow: (List String) -> (Pair (List String) (List String))
  (let [(grown (excess allow baseAllow))]
    (pair (filter (fn [(k String)] -> Bool (not (fixture? k))) grown) (filter fixture? grown)))

fn q s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn qs xs: (List String) -> String
  (str "(" (stringJoin (map q xs) " ") ")")

fn receiptWith v: Verdict allowed: Int64 grown: (List String) extra: String -> String
  (str "(:vcsDirectAudit :v 1 :status :" (if (and (listEmpty? v.newSites) (and (listEmpty? v.stale) (listEmpty? grown))) "ok" "violation")
       " :sites " (stringFromInt64 (listLength v.found)) " :allowed " (stringFromInt64 allowed)
       " :new " (qs v.newSites) " :stale " (qs v.stale) extra ")")

fn receiptOf v: Verdict allowed: Int64 -> String
  (receiptWith v allowed (list) "")

; (:m :do "tracked .asl paths from git ls-files in root, a failed listing is an error, never an empty tree")
fn ! trackedAsl! root: String -> (Result (List String) String)
  (match (sr/gitOut! root (list "ls-files" "--" "*.asl"))
    ((err e) (err e))
    ((ok out) (ok (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (map stringTrim (stringLines out))))))

fn readCause r: (Result String String) -> String
  (match r ((err e) e) ((ok _) ""))

; (:m :do "path and text of every tracked .asl file; a file that cannot be read is an error naming the path and its cause, never an empty file")
fn ! readTracked! root: String -> (Result (List (Pair String String)) String)
  (match (trackedAsl! root)
    ((err e) (err (str "cannot list tracked files: " e)))
    ((ok paths)
      (let [(reads (map (fn [(p String)] -> (Pair String (Result String String)) (pair p (fileReadString (str root "/" p)))) paths))
            (bad (filter (fn [(r (Pair String (Result String String)))] -> Bool (not (ok? (pairSecond r)))) reads))]
        (match (listHead bad)
          ((some b) (err (str "cannot read " (pairFirst b) ": " (readCause (pairSecond b)))))
          ((none) (ok (map (fn [(r (Pair String (Result String String)))] -> (Pair String String) (pair (pairFirst r) (resultOr (pairSecond r) ""))) reads)))))))

fn allowRel -> String
  ".asl/mem/vcsDirectAllow.asn"

; (:m :do "the base commit: --base REF resolved, by default the merge base of HEAD with main; a base that does not resolve is an error")
fn ! baseCommit! root: String base: String -> (Result String String)
  (if (stringEmpty? base)
    (match (sr/gitOut! root (list "merge-base" "HEAD" "main"))
      ((ok sha) (ok (stringTrim sha)))
      ((err e) (err (str "ERR_VCS_NO_MAIN: no main branch to compare with, or not a git work tree (" e ")"))))
    (resultMap (sr/gitOut! root (list "rev-parse" "--verify" (str base "^{commit}"))) stringTrim))

; (:m :do "the allowlist keys at the base commit; none when the allowlist did not exist there yet, an error when git fails")
fn ! baseAllow! root: String sha: String -> (Result (Option (List String)) String)
  (match (sr/gitOut! root (list "ls-tree" "--name-only" sha "--" (allowRel)))
    ((err e) (err e))
    ((ok listed)
      (if (stringEmpty? (stringTrim listed))
        (ok none)
        (match (sr/gitOut! root (list "show" (str sha ":" (allowRel))))
          ((err e) (err e))
          ((ok text) (ok (some (parseAllow text))))))))

fn baseRowsText baseKeys: (Option (List String)) -> String
  (match baseKeys ((some b) (stringFromInt64 (listLength b))) ((none) ":absent"))

fn grownFor allow: (List String) baseKeys: (Option (List String)) -> (Pair (List String) (List String))
  (match baseKeys ((some b) (grownOf allow b)) ((none) (pair (list) (list))))

; (:m :ref VCS-AUDIT-SPEED :do "per-file scan cache: the result of scanning one file (its helper keys and its sites) depends only on its content and on the helper view it is scanned with, so the row key is sha256(content) | digest(all helper names) | the file's own helper names; an unchanged file in an unchanged helper set is never tokenized again; the cache lives in .asl/cache (ignored by git) and holds only the rows this run used")
fn itemSep -> String
  "~|~"

fn contentSha text: String -> String
  (bytesSha256 (stringToBytes text))

fn namesDigest h: Helpers -> String
  (contentSha (stringJoin (listSort h.names) " "))

fn viewKey sha: String hd: String h: Helpers file: String -> String
  (str sha "|" hd "|" (if (excluded? file) "x" "n") "|" (stringJoin (listSort (map keyName (filter (fn [(k String)] -> Bool (stringStartsWith? k (str file "|"))) h.local))) " "))

; (:m :do "one cache row: key TAB helper symbols TAB sites as verb-space-symbol, items joined by the item separator")
fn encodeRow key: String found: (List String) sites: (List Site) file: String -> String
  (str key "\t" (stringJoin (map (fn [(k String)] -> String (optionOr (stringSlice k (+ (stringLength file) 1) (stringLength k)) k)) found) (itemSep))
       "\t" (stringJoin (map (fn [(s Site)] -> String (str s.verb " " s.symbol)) sites) (itemSep)))

fn decodeRes file: String row: String -> (Pair (List String) (List Site))
  (let [(parts (stringSplit row "\t"))
        (items (fn [(i Int64)] -> (List String) (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (stringSplit (optionOr (listGet parts i) "") (itemSep)))))]
    (pair (map (fn [(n String)] -> String (str file "|" n)) (items 0))
          (map (fn [(it String)] -> Site (let [(at (optionOr (listIndexOf (stringChars it) " ") 0))]
                                           (Site :file file :verb (optionOr (stringSlice it 0 at) "") :symbol (optionOr (stringSlice it (+ at 1) (stringLength it)) ""))))
               (items 1))))

; (:m :do "the rows of a cache text as a map key to the row text after the key; a malformed line is dropped, never a failure")
fn parseCache text: String -> (Map String String)
  (fold (fn [(m (Map String String)) (l String)] -> (Map String String)
          (let [(i (optionOr (listIndexOf (stringChars l) "\t") -1))]
            (if (< i 1) m (mapSet m (optionOr (stringSlice l 0 i) "") (optionOr (stringSlice l (+ i 1) (stringLength l)) "")))))
        (mapEmpty) (stringLines text))

; (:m :do "scan one file through the cache: a hit decodes the stored row, a miss tokenizes and scans; the row used is recorded in the used map")
fn scanOne old: (Map String String) used: (Map String String) sha: String hd: String h: Helpers file: String text: String -> (Pair (Pair (List String) (List Site)) (Map String String))
  (let [(key (viewKey sha hd h file))]
    (match (mapGet old key)
      ((some row) (pair (decodeRes file row) (mapSet used key row)))
      ((none)
       (let [(sc (scanToks (helpersFor h file) file (lex/tokenize text)))
             (found sc.found)
             (sites (if (excluded? file) (list) (listReverse sc.sites)))
             (row (stringReplace (encodeRow key found sites file) (str key "\t") ""))]
         (pair (pair found sites) (mapSet used key row))))))

fn scanAllFiles old: (Map String String) shas: (Map String String) h: Helpers files: (List (Pair String String)) -> (Pair (List (Pair String (Pair (List String) (List Site)))) (Map String String))
  (let [(hd (namesDigest h))
        (step (fn [(acc (Pair (List (Pair String (Pair (List String) (List Site)))) (Map String String))) (f (Pair String String))] -> (Pair (List (Pair String (Pair (List String) (List Site)))) (Map String String))
                (let [(r (scanOne old (pairSecond acc) (optionOr (mapGet shas (pairFirst f)) "") hd h (pairFirst f) (pairSecond f)))]
                  (pair (cons (pair (pairFirst f) (pairFirst r)) (pairFirst acc)) (pairSecond r)))))
        (done (fold step (pair (list) (mapEmpty)) files))]
    (pair (listReverse (pairFirst done)) (pairSecond done)))

fn mergeUsed a: (Map String String) b: (Map String String) -> (Map String String)
  (fold (fn [(m (Map String String)) (k String)] -> (Map String String) (mapSet m k (optionOr (mapGet b k) ""))) a (mapKeys b))

; (:m :do "the helper fixpoint of helperLoop with the cache: only files whose text holds git are scanned per round")
fn helperLoopC old: (Map String String) shas: (Map String String) files: (List (Pair String String)) h: Helpers rounds: Int64 used: (Map String String) -> (Pair Helpers (Map String String))
  (let [(r (scanAllFiles old shas h files))
        (found (unique (listAppend h.local (listFlatMap (fn [(x (Pair String (Pair (List String) (List Site))))] -> (List String) (pairFirst (pairSecond x))) (pairFirst r)))))
        (used2 (mergeUsed used (pairSecond r)))]
    (if (or (<= rounds 0) (= (listLength found) (listLength h.local)))
      (pair (helpersFrom found) used2)
      (helperLoopC old shas files (helpersFrom found) (- rounds 1) used2)))

; (:m :do "the sites of a tree with the cache: (sites, used rows); equal to scanFiles for any cache content")
fn scanFilesC old: (Map String String) files: (List (Pair String String)) -> (Pair (List Site) (Map String String))
  (let [(shas (fold (fn [(m (Map String String)) (f (Pair String String))] -> (Map String String) (mapSet m (pairFirst f) (contentSha (pairSecond f)))) (mapEmpty) files))
        (gitFiles (filter (fn [(f (Pair String String))] -> Bool (and (not (excluded? (pairFirst f))) (stringContains? (pairSecond f) "git"))) files))
        (hl (helperLoopC old shas gitFiles (Helpers :local (list) :names (list)) 8 (mapEmpty)))
        (all (scanAllFiles old shas (pairFirst hl) files))]
    (pair (listFlatMap (fn [(x (Pair String (Pair (List String) (List Site))))] -> (List Site) (pairSecond (pairSecond x))) (pairFirst all))
          (mergeUsed (pairSecond hl) (pairSecond all))))

fn cacheText used: (Map String String) -> String
  (stringJoin (map (fn [(k String)] -> String (str k "\t" (optionOr (mapGet used k) ""))) (listSort (mapKeys used))) "\n")

; (:m :ref VCS-AUDIT-LOWS-F1 :do "the cache lives outside every worktree, in the runner-owned store HOME/.asl/run/vcsDirect/ID where ID is the first 16 hex of sha256 of the real git common dir, so a worktree cannot commit it, but any writer of the same user can alter it: the cache is a speed aid and is never trusted, merge-time runs use mode off (--no-cache); mode off reads and writes nothing (merge-time runs), a dir argument replaces the store (tests)")
fn storeRoot -> String
  (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/vcsDirect")

fn ! cacheDirFor! root: String mode: String -> Result String String
  (cond
    ((= mode "off") (ok ""))
    ((not (stringEmpty? mode)) (ok mode))
    (else
      (match (sr/gitOut! root (list "rev-parse" "--git-common-dir"))
        ((err e) (err (str "git common dir: " e)))
        ((ok out)
          (let [(raw (stringTrim out))
                (abs (if (stringStartsWith? raw "/") raw (str root "/" raw)))
                (real (resultOr (realPath abs) abs))]
            (ok (str (storeRoot) "/" (optionOr (stringSlice (contentSha real) 0 16) "x"))))))))

; (:m :do "load the cache file of dir (absent or unreadable is an empty cache), scan, and write the rows used when they differ from the loaded ones; dir empty means no cache; the second value is empty or the reason the cache could not be written, reported in the receipt")
fn ! scanCached! dir: String files: (List (Pair String String)) -> (Pair (List Site) String)
  (if (stringEmpty? dir)
    (pair (scanFiles files) "")
    (let [(path (str dir "/vcsDirectAudit.v1"))
          (old (parseCache (resultOr (fileReadString path) "")))
          (r (scanFilesC old files))
          (used (pairSecond r))
          (changed (or (!= (mapSize used) (mapSize old)) (listAny? (fn [(k String)] -> Bool (not (some? (mapGet old k)))) (mapKeys used))))]
      (pair (pairFirst r)
            (if (not changed) ""
              (match (dirCreate dir)
                ((err e) (str "cache dir: " e))
                ((ok _) (match (fileWrite path (cacheText used)) ((err e) (str "cache write: " e)) ((ok _) ""))))))))

fn verdictReceipt sites: (List Site) note: String text: String sha: String head: String baseKeys: (Option (List String)) -> String
  (let [(allow (parseAllow text))
        (v (verdictOf sites allow))
        (grown (grownFor allow baseKeys))
        (extra (str " :base " (if (= sha head) ":self" (q sha)) " :baseRows " (baseRowsText baseKeys) " :grown " (qs (pairFirst grown)) " :grownFixtures " (qs (pairSecond grown)) (if (stringEmpty? note) "" (str " :cache " (q note)))))]
    (receiptWith v (listLength allow) (pairFirst grown) extra))

; (:m :do "the receipt with the base (:self when the base is HEAD itself, as on main, so the ratchet compares against the committed allowlist) and the run time :ms")
fn ! auditAt! root: String allowPath: String base: String -> (Result String String)
  (auditWith! root allowPath base "")

; (:m :do "cache is empty for the runner store, off for no cache, or a directory")
fn ! auditWith! root: String allowPath: String base: String cache: String -> (Result String String)
  (let [(t0 (/ (nowNs) 1000000))
        (r (auditCore! root allowPath base cache))
        (ms (- (/ (nowNs) 1000000) t0))]
    (match r
      ((err e) (err e))
      ((ok s) (ok (str (optionOr (stringSlice s 0 (- (stringLength s) 1)) s) " :ms " (stringFromInt64 ms) ")")))))

fn ! trackedCache! root: String -> (Result (List String) String)
  (match (sr/gitOut! root (list "ls-files" "--" ".asl/cache/vcsDirectAudit*"))
    ((err e) (err e))
    ((ok out) (ok (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (map stringTrim (stringLines out))))))

fn ! auditCore! root: String allowPath: String base: String cache: String -> (Result String String)
  (match (trackedCache! root)
    ((err e) (err (str "cannot list tracked cache paths: " e)))
    ((ok tracked)
  (if (not (listEmpty? tracked))
    (err (str "ERR_VCS_CACHE_TRACKED: tracked paths under .asl/cache would forge a scan cache: " (stringJoin (listTake tracked 5) ",")))
  (match (readTracked! root)
    ((err e) (err e))
    ((ok files)
      (match (fileReadString allowPath)
        ((err e) (err (str "cannot read the allowlist " allowPath ": " e)))
        ((ok text)
          (match (baseCommit! root base)
            ((err e) (err (str "cannot resolve the base: " e)))
            ((ok sha)
              (match (baseAllow! root sha)
                ((err e) (err (str "cannot read the allowlist at the base " sha ": " e)))
                ((ok baseKeys)
                  (match (sr/gitOut! root (list "rev-parse" "HEAD"))
                    ((err e) (err (str "cannot resolve HEAD: " e)))
                    ((ok head) (match (cacheDirFor! root cache)
                      ((err e) (err e))
                      ((ok dir) (let [(sc (scanCached! dir files))] (ok (verdictReceipt (pairFirst sc) (pairSecond sc) text sha (stringTrim head) baseKeys))))))))))))))))))

fn ! audit! root: String allowPath: String -> (Result String String)
  (auditAt! root allowPath "")

fn countOf xs: (List String) x: String -> Int64
  (listCount (fn [(y String)] -> Bool (= y x)) xs)

fn firstSites sites: (List Site) -> (List Site)
  (listReverse (pairSecond (fold (fn [(acc (Pair (List String) (List Site))) (s Site)] -> (Pair (List String) (List Site))
                                   (if (listContains? (pairFirst acc) (siteKey s)) acc (pair (cons (siteKey s) (pairFirst acc)) (cons s (pairSecond acc)))))
                                 (pair (list) (list)) sites)))

; (:m :do "baseline rows for every current site key with its count, to seed or review the allowlist")
fn emitRows sites: (List Site) why: String -> String
  (let [(keys (map siteKey sites))]
    (stringJoin (map (fn [(s Site)] -> String
                       (let [(n (countOf keys (siteKey s)))]
                         (str "(:site " (q (str s.file "#" s.symbol)) " :file " (q s.file) " :symbol " (q s.symbol) " :argv " (q (str "git " s.verb))
                              (if (> n 1) (str " :n " (stringFromInt64 n)) "") " :why " (q why) ")")))
                     (firstSites sites)) "\n"))

fn flagAfter args: (List String) name: String -> String
  (match (listIndexOf args name)
    ((none) "")
    ((some i) (optionOr (listGet args (+ i 1)) "")))

fn ! failWith e: String -> (Result Int64 String)
  (do (println (str "(:vcsDirectAudit :status :error :why " (q e) ")")) (ok 2))

; (:m :do "cache mode of the command line: --no-cache is off, --cache-dir D is a directory, else the runner store")
fn cap args: (List String) -> String
  (if (listContains? args "--no-cache") "off" (flagAfter args "--cache-dir"))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(rootFlag (flagAfter args "--root"))
        (root (if (stringEmpty? rootFlag) "." rootFlag))
        (allowFlag (flagAfter args "--allow"))
        (allowPath (if (stringEmpty? allowFlag) (str root "/" (allowRel)) allowFlag))]
    (cond
      ((listContains? args "--emit")
        (match (readTracked! root)
          ((err e) (failWith e))
          ((ok files) (do (println (emitRows (scanFiles files) "baseline: raw git before the vcs layer migration, VCS-DIRECT-GIT-AUDIT")) (ok 0)))))
      ((listContains? args "--helpers")
        (match (readTracked! root)
          ((err e) (failWith e))
          ((ok files) (do (println (str "(:vcsHelpers " (qs (helpersOf files).local) ")")) (ok 0)))))
      (else
        (match (auditWith! root allowPath (flagAfter args "--base") (cap args))
          ((err e) (failWith e))
          ((ok receipt) (do (println receipt) (ok (if (stringContains? receipt ":status :ok") 0 1))))))))
