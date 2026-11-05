(module asl-gates/vcsDirectAudit
  :x [Site Verdict scanSource scanFiles verdictOf allowKeys parseAllow siteKey receiptOf audit! trackedAsl! emitRows main vcsVerbs excluded?]
  :i [(asl-parser/lexer :a lex) (asl-gates/suiteRunner :a sr)])

; (:m :ref VCS-DIRECT-GIT-AUDIT :do "finds literal git argv outside asl/tools/vcs: a (list or (cons form that starts with the string git, a call of a git-named helper, or a string starting with git, whose first non-option literal is commit, add, update-ref, commit-tree, push, reset or checkout; each site is keyed path#symbol plus the verb, never a line; the allowlist .asl/mem/vcsDirectAllow.asn only shrinks: a new site is a violation and an allowlist row without a site is a violation; comments and strings that merely contain git text are not sites; asl run asl/packages/asl-gates/src/vcsDirectAudit.asl [--root DIR] [--allow FILE] [--emit] prints one ASN receipt, exit 0 clean, 1 violation, 2 error")
(schema Site
  (:f file String)
  (:f symbol String)
  (:f verb String))

(schema Verdict
  (:f found (List Site))
  (:f newSites (List String))
  (:f stale (List String)))

(schema Coll
  (:f depth Int64)
  (:f strs (List String))
  (:f helper Bool))

(schema Scan
  (:f symbol String)
  (:f prev1 String)
  (:f prev2 String)
  (:f coll (Option Coll))
  (:f sites (List Site)))

fn vcsVerbs -> (List String)
  (list "commit" "add" "update-ref" "commit-tree" "push" "reset" "checkout")

fn excluded? path: String -> Bool
  (stringStartsWith? path "asl/tools/vcs/")

fn unquote raw: String -> String
  (if (and (stringStartsWith? raw "\"") (>= (stringLength raw) 2))
    (stringReplace (optionOr (stringSlice raw 1 (- (stringLength raw) 1)) "") "\\\"" "\"")
    raw)

fn baseName name: String -> String
  (optionOr (listLast (stringSplit name "/")) name)

fn gitHelper? name: String -> Bool
  (let [(b (baseName name))]
    (and (stringStartsWith? b "git")
         (or (stringEndsWith? b "!") (listContains? (list "gitIn" "gitOut" "gitRun" "gitCmd") b))))

fn option? s: String -> Bool
  (or (stringStartsWith? s "-") (stringContains? s "="))

; (:m :do "the verb of a literal list: the first literal after git that is not an option (-C, --x, k=v); none when it is not a destructive verb")
fn verbOf strs: (List String) -> (Option String)
  (let [(words (filter (fn [(s String)] -> Bool (and (not (stringEmpty? s)) (and (!= s "git") (not (option? s))))) strs))]
    (match (listHead words)
      ((some w) (if (listContains? (vcsVerbs) w) (some w) none))
      ((none) none)))

fn stringVerb text: String -> (Option String)
  (if (stringStartsWith? text "git ")
    (verbOf (stringSplit text " "))
    none)

fn addSite scan: Scan file: String verb: String -> Scan
  (let [(s (Site :file file :symbol scan.symbol :verb verb))]
    (if (listAny? (fn [(x Site)] -> Bool (and (= x.symbol s.symbol) (= x.verb s.verb))) scan.sites)
      scan
      (Scan :symbol scan.symbol :prev1 scan.prev1 :prev2 scan.prev2 :coll scan.coll :sites (cons s scan.sites))))

fn step file: String scan: Scan tok: lex/Token -> Scan
  (let [(kind tok.kind)
        (text (match kind ((lex/tokSymbol n) n) ((lex/tokString v) (unquote v)) (_ "")))
        (isStr (match kind ((lex/tokString _) true) (_ false)))
        (isSym (match kind ((lex/tokSymbol _) true) (_ false)))
        (isOpen (match kind ((lex/tokLparen) true) ((lex/tokLbracket) true) (_ false)))
        (isClose (match kind ((lex/tokRparen) true) ((lex/tokRbracket) true) (_ false)))
        (symbol (cond
                  ((and isSym (and (<= tok.col 1) (= text "fn"))) "<fn>")
                  ((and isSym (= scan.symbol "<fn>")) (if (= text "!") "<fn>" text))
                  (else scan.symbol)))
        (afterColl (match scan.coll
                     ((some c)
                       (cond
                         (isOpen (some (Coll :depth (+ c.depth 1) :strs c.strs :helper c.helper)))
                         (isClose (if (<= c.depth 1) none (some (Coll :depth (- c.depth 1) :strs c.strs :helper c.helper))))
                         (isStr (some (Coll :depth c.depth :strs (cons text c.strs) :helper c.helper)))
                         (else (some c))))
                     ((none) none)))
        (closed (match scan.coll ((some c) (and isClose (<= c.depth 1))) ((none) false)))
        (opened (cond
                  ((and isStr (and (= text "git") (and (= scan.prev2 "(") (listContains? (list "list" "cons") scan.prev1))))
                    (some (Coll :depth 1 :strs (list "git") :helper false)))
                  ((and isSym (and (= scan.prev1 "(") (gitHelper? text)))
                    (some (Coll :depth 1 :strs (list) :helper true)))
                  (else none)))
        (base (Scan :symbol symbol :prev1 (if isOpen "(" text) :prev2 scan.prev1
                    :coll (match opened ((some o) (some o)) ((none) afterColl)) :sites scan.sites))
        (withColl (if closed
                    (match scan.coll
                      ((some c) (match (verbOf (listReverse c.strs)) ((some v) (addSite base file v)) ((none) base)))
                      ((none) base))
                    base))]
    (if (and isStr (not (excluded? file)))
      (match (stringVerb text)
        ((some v) (addSite withColl file v))
        ((none) withColl))
      withColl))

; (:m :do "the sites of one source text, in no particular order, empty for a file under asl/tools/vcs")
fn scanSource file: String source: String -> (List Site)
  (if (excluded? file)
    (list)
    (listReverse (fold (fn [(acc Scan) (t lex/Token)] -> Scan (step file acc t))
                       (Scan :symbol "<top>" :prev1 "" :prev2 "" :coll none :sites (list))
                       (lex/tokenize source)).sites))

fn scanFiles files: (List (Pair String String)) -> (List Site)
  (listFlatMap (fn [(f (Pair String String))] -> (List Site) (scanSource (pairFirst f) (pairSecond f))) files)

fn siteKey s: Site -> String
  (str s.file "#" s.symbol "|git " s.verb)

; (:m :do "the (site, argv) keys of an allowlist text: every :site string paired in order with the :argv string after it")
fn parseAllow text: String -> (List String)
  (let [(toks (lex/tokenize text))
        (strs (fold (fn [(acc (Pair String (List String))) (t lex/Token)] -> (Pair String (List String))
                      (match t.kind
                        ((lex/tokKeyword k) (pair k (pairSecond acc)))
                        ((lex/tokString v) (if (listContains? (list ":site" ":argv") (pairFirst acc))
                                              (pair "" (cons (str (pairFirst acc) (unquote v)) (pairSecond acc)))
                                              acc))
                        (_ acc)))
                    (pair "" (list)) toks))]
    (pairKeys (listReverse (pairSecond strs))))

fn pairKeys xs: (List String) -> (List String)
  (match (listHead xs)
    ((none) (list))
    ((some a)
      (let [(rest (optionOr (listTail xs) (list)))]
        (match (listHead rest)
          ((none) (list))
          ((some b) (cons (str (stringReplace a ":site" "") "|" (stringReplace b ":argv" "")) (pairKeys (optionOr (listTail rest) (list)))))))))

fn allowKeys text: String -> (List String)
  (parseAllow text)

fn verdictOf sites: (List Site) allow: (List String) -> Verdict
  (let [(keys (map siteKey sites))]
    (Verdict :found sites
             :newSites (filter (fn [(k String)] -> Bool (not (listContains? allow k))) keys)
             :stale (filter (fn [(k String)] -> Bool (not (listContains? keys k))) allow)))

fn q s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn qs xs: (List String) -> String
  (str "(" (stringJoin (map q xs) " ") ")")

fn receiptOf v: Verdict allowed: Int64 -> String
  (str "(:vcsDirectAudit :v 1 :status :" (if (and (listEmpty? v.newSites) (listEmpty? v.stale)) "ok" "violation")
       " :sites " (stringFromInt64 (listLength v.found)) " :allowed " (stringFromInt64 allowed)
       " :new " (qs v.newSites) " :stale " (qs v.stale) ")")

; (:m :do "tracked .asl paths from git ls-files in root, a failed listing is an error, never an empty tree")
fn ! trackedAsl! root: String -> (Result (List String) String)
  (match (sr/gitOut! root (list "ls-files" "--" "*.asl"))
    ((err e) (err e))
    ((ok out) (ok (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (map stringTrim (stringLines out))))))

fn ! audit! root: String allowPath: String -> (Result String String)
  (match (trackedAsl! root)
    ((err e) (err (str "cannot list tracked files: " e)))
    ((ok paths)
      (match (fileReadString allowPath)
        ((err e) (err (str "cannot read the allowlist " allowPath ": " e)))
        ((ok text)
          (let [(files (map (fn [(p String)] -> (Pair String String) (pair p (resultOr (fileReadString (str root "/" p)) ""))) paths))
                (allow (parseAllow text))
                (v (verdictOf (scanFiles files) allow))]
            (ok (receiptOf v (listLength allow))))))))

; (:m :do "baseline rows for every current site, to seed or review the allowlist")
fn emitRows sites: (List Site) why: String -> String
  (stringJoin (map (fn [(s Site)] -> String
                     (str "(:site " (q (str s.file "#" s.symbol)) " :file " (q s.file) " :symbol " (q s.symbol) " :argv " (q (str "git " s.verb)) " :why " (q why) ")"))
                   sites) "\n")

fn ! main args: (List String) -> (Result Int64 String)
  (let [(rootFlag (flagAfter args "--root"))
        (root (if (stringEmpty? rootFlag) "." rootFlag))
        (allowFlag (flagAfter args "--allow"))
        (allowPath (if (stringEmpty? allowFlag) (str root "/.asl/mem/vcsDirectAllow.asn") allowFlag))]
    (if (listContains? args "--emit")
      (match (trackedAsl! root)
        ((err e) (do (println (str "(:vcsDirectAudit :status :error :why " (q e) ")")) (ok 2)))
        ((ok paths) (do (println (emitRows (scanFiles (map (fn [(p String)] -> (Pair String String) (pair p (resultOr (fileReadString (str root "/" p)) ""))) paths))
                                           "baseline: raw git before the vcs layer migration, VCS-DIRECT-GIT-AUDIT"))
                        (ok 0))))
      (match (audit! root allowPath)
        ((err e) (do (println (str "(:vcsDirectAudit :status :error :why " (q e) ")")) (ok 2)))
        ((ok receipt) (do (println receipt) (ok (if (stringContains? receipt ":status :ok") 0 1)))))))

fn flagAfter args: (List String) name: String -> String
  (match (listIndexOf args name)
    ((none) "")
    ((some i) (optionOr (listGet args (+ i 1)) "")))
