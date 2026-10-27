(module asl-utils/kit
  :x [Kit Flag Out Op Diff specOf parse help run! flag flagInt flagOn? arg argNum env glob! globGit! globRegex readText! readLines! writeText! inside? edit! editAll! editRx! replaceAll sub found? diff sh! shFor! quote]
  :i [(asl-tools/fleet/run :a fr) (asl-regex/regex :a re)])

; (:m :ref SCRIPT-KIT :do "script kit: flags typed by their defaults with generated help, positional args, read-only env, sorted glob, atomic writes, confined edits that print a unified diff under --dry, regex text helpers and argv-only children through fleet/run; every action prints one ASN receipt line")
(schema Flag
  (:f name String)
  (:f kind String)
  (:f value String)
  (:f note String))

(schema Kit
  (:f flags (List Flag))
  (:f vals (Map String String))
  (:f args (List String))
  (:f help Bool)
  (:f dry Bool)
  (:f outside Bool)
  (:f root String))

(schema Out
  (:f exit Int64)
  (:f out String)
  (:f err String))

(schema Op
  (:f tag String)
  (:f text String)
  (:f ai Int64)
  (:f bi Int64))

(schema Diff
  (:f text String)
  (:f hunks Int64))

(schema Hunks
  (:f ctx (List Op))
  (:f cur (List Op))
  (:f open Bool)
  (:f trail Int64)
  (:f done (List (List Op))))

fn quote s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\"")

fn kindOf value: String -> String
  (cond ((or (= value "true") (= value "false")) "bool")
        ((some? (stringToInt64 value)) "int")
        (else "str"))

fn specItem item: String -> Flag
  (match (stringIndexOf item "=")
    ((some i) (let [(v (optionOr (stringSlice item (+ i 1) (stringLength item)) ""))]
                (Flag :name (optionOr (stringSlice item 0 i) item) :kind (kindOf v) :value v :note "")))
    ((none) (Flag :name item :kind "bool" :value "false" :note "")))

fn declared? flags: (List Flag) name: String -> Bool
  (listAny? (fn [(f Flag)] -> Bool (= f.name name)) flags)

fn withBuiltin flags: (List Flag) b: Flag -> (List Flag)
  (if (declared? flags b.name) flags (listAppend flags (list b)))

fn specOf text: String -> (List Flag)
  (let [(own (map specItem (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit text " "))))]
    (withBuiltin (withBuiltin own (Flag :name "dry" :kind "bool" :value "false" :note "print a unified diff instead of writing"))
                 (Flag :name "allow-outside" :kind "bool" :value "false" :note "let edits leave the current directory")))

fn known flags: (List Flag) -> String
  (str (stringJoin (map (fn [(f Flag)] -> String (str "--" f.name)) flags) " ") " --help")

fn flagNamed flags: (List Flag) name: String -> (Option Flag)
  (listFind (fn [(f Flag)] -> Bool (= f.name name)) flags)

fn setFlag k: Kit f: Flag value: (Option String) rest: (List String) -> (Result (Pair Kit (List String)) String)
  (cond
    ((= f.kind "bool")
      (match value
        ((none) (ok (pair (with k :vals (mapSet k.vals f.name "true")) rest)))
        ((some v) (if (= (kindOf v) "bool")
                    (ok (pair (with k :vals (mapSet k.vals f.name v)) rest))
                    (err (str "flag --" f.name " takes true or false, given " (quote v)))))))
    (else
      (let [(taken (match value
                     ((some v) (some (pair v rest)))
                     ((none) (match (listHead rest) ((some v) (some (pair v (listDrop rest 1)))) ((none) (none))))))]
        (match taken
          ((none) (err (str "flag --" f.name " needs a value")))
          ((some vr)
            (if (and (= f.kind "int") (none? (stringToInt64 (pairFirst vr))))
              (err (str "flag --" f.name " takes an integer, given " (quote (pairFirst vr))))
              (ok (pair (with k :vals (mapSet k.vals f.name (pairFirst vr))) (pairSecond vr)))))))))

fn longFlag k: Kit tok: String rest: (List String) -> (Result (Pair Kit (List String)) String)
  (let [(body (optionOr (stringSlice tok 2 (stringLength tok)) ""))
        (eq (stringIndexOf body "="))
        (name (match eq ((some i) (optionOr (stringSlice body 0 i) body)) ((none) body)))
        (value (match eq ((some i) (stringSlice body (+ i 1) (stringLength body))) ((none) (none))))]
    (match (flagNamed k.flags name)
      ((some f) (setFlag k f value rest))
      ((none) (err (str "unknown flag " tok "; known: " (known k.flags))))))

fn positional? tok: String literal: Bool -> Bool
  (or literal (or (= tok "-") (or (not (stringStartsWith? tok "-")) (some? (stringToInt64 tok)))))

fn parseFrom k: Kit argv: (List String) literal: Bool -> (Result Kit String)
  (match (listHead argv)
    ((none) (ok (with k :args (listReverse k.args) :dry (= (mapGetOr k.vals "dry" "false") "true") :outside (= (mapGetOr k.vals "allow-outside" "false") "true"))))
    ((some tok)
      (let [(rest (listDrop argv 1))]
        (cond
          ((positional? tok literal) (parseFrom (with k :args (cons tok k.args)) rest literal))
          ((= tok "--") (parseFrom k rest true))
          ((or (= tok "-h") (= tok "--help")) (parseFrom (with k :help true) rest literal))
          ((stringStartsWith? tok "--")
            (match (longFlag k tok rest)
              ((err e) (err e))
              ((ok kr) (parseFrom (pairFirst kr) (pairSecond kr) literal))))
          (else (err (str "unknown flag " tok "; known: " (known k.flags))))))))

fn parse argv: (List String) spec: String -> (Result Kit String)
  (let [(flags (specOf spec))]
    (parseFrom (Kit :flags flags :vals (mapFromPairs (map (fn [(f Flag)] -> (Pair String String) (pair f.name f.value)) flags)) :args (list) :help false :dry false :outside false :root "") argv false))

fn helpLine f: Flag -> String
  (let [(arg (cond ((= f.kind "int") " INT") ((= f.kind "str") " STR") (else "")))
        (dflt (if (= f.kind "bool") "" (str " (default " f.value ")")))
        (note (if (stringEmpty? f.note) "" (str "  " f.note)))]
    (str "  --" f.name arg dflt note "\n"))

fn help k: Kit -> String
  (str "usage: [flags] [args]\n" (stringJoin (map helpLine k.flags) "") "  -h, --help  this text\n")

fn rooted k: Kit root: String -> Kit
  (with k :root root)

fn ! run! argv: (List String) spec: String body: (fn [Kit] -> (Result Unit String)) -> (Result Unit String)
  (match (parse argv spec)
    ((err e) (err e))
    ((ok k)
      (if k.help
        (do (print (help k)) (ok ()))
        (match (realPath ".")
          ((err e) (err e))
          ((ok root) (body (rooted k root)))))))

fn flag k: Kit name: String -> String
  (match (mapGet k.vals name)
    ((some v) v)
    ((none) (trap "ERR_ARG" (str "flag --" name " is not declared; known: " (known k.flags)))))

fn flagInt k: Kit name: String -> Int64
  (match (stringToInt64 (flag k name))
    ((some n) n)
    ((none) (trap "ERR_ARG" (str "flag --" name " is not an integer flag"))))

fn flagOn? k: Kit name: String -> Bool
  (= (flag k name) "true")

fn arg k: Kit i: Int64 fallback: String -> String
  (argStr k.args i fallback)

fn argNum k: Kit i: Int64 fallback: Int64 -> Int64
  (argInt k.args i fallback)

fn ! env name: String fallback: String -> String
  (optionOr (envGet name) fallback)

fn at s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

fn globRx pat: String i: Int64 acc: String -> String
  (if (>= i (stringLength pat))
    acc
    (let [(c (at pat i))]
      (cond
        ((and (= c "*") (= (at pat (+ i 1)) "*"))
          (if (= (at pat (+ i 2)) "/")
            (globRx pat (+ i 3) (str acc "(?:.*/)?"))
            (globRx pat (+ i 2) (str acc ".*"))))
        ((= c "*") (globRx pat (+ i 1) (str acc "[^/]*")))
        ((= c "?") (globRx pat (+ i 1) (str acc "[^/]")))
        ((stringContains? ".+()|^$}{[]\\" c) (globRx pat (+ i 1) (str acc "\\" c)))
        (else (globRx pat (+ i 1) (str acc c))))))

fn globRegex pat: String -> String
  (str "^" (globRx pat 0 "") "$")

fn wild? seg: String -> Bool
  (or (stringContains? seg "*") (stringContains? seg "?"))

fn joinPath rel: String name: String -> String
  (if (stringEmpty? rel) name (if (stringEndsWith? rel "/") (str rel name) (str rel "/" name)))

fn ! walk! r: re/Regex rel: String depth: Int64 acc: (List String) -> (List String)
  (match (dirList (if (stringEmpty? rel) "." rel))
    ((err e) (do (eprintln (str "(:skipped " (quote rel) " :why " (quote e) ")")) acc))
    ((ok names)
      (fold (fn [(a (List String)) (name String)] -> (List String)
              (let [(p (joinPath rel name))]
                (if (or (= name ".git") (or (= name ".") (= name "..")))
                  a
                  (match (fileLstat p)
                    ((err _) a)
                    ((ok st)
                      (cond
                        ((and st.isDir (> depth 1)) (walk! r p (- depth 1) a))
                        ((and st.isDir (not st.isSymlink)) a)
                        ((re/regex-match? r p) (cons p a))
                        (else a)))))))
            acc names)))

fn ! glob! pat: String -> (List String)
  (match (re/regex-compile! (globRegex pat))
    ((err e) (trap "ERR_IO" (str "glob " (quote pat) ": " e)))
    ((ok r)
      (let [(segs (stringSplit pat "/"))
            (lead (listTake segs (- (listLength segs) 1)))
            (base (listTake lead (optionOr (listIndexOf (map wild? lead) true) (listLength lead))))
            (depth (if (stringContains? pat "**") 64 (- (listLength segs) (listLength base))))]
        (listSort (walk! r (stringJoin base "/") depth (list))))))

fn ! globGit! pat: String -> (List String)
  (match (re/regex-compile! (globRegex pat))
    ((err e) (trap "ERR_IO" (str "glob " (quote pat) ": " e)))
    ((ok r)
      (let [(o (sh! (list "git" "ls-files" "--cached" "--others" "--exclude-standard")))]
        (if (!= o.exit 0)
          (trap "ERR_IO" (str "git ls-files failed with exit " o.exit ": " (stringReplace (stringTrim o.err) "\n" " ")))
          (listSort (filter (fn [(p String)] -> Bool (and (re/regex-match? r p) (fileExists? p))) (stringLines o.out)))))))

fn ! readText! p: String -> (Result String String)
  (fileReadString p)

fn ! readLines! p: String -> (Result (List String) String)
  (match (fileReadString p)
    ((ok t) (ok (map (fn [(l String)] -> String (if (stringEndsWith? l "\n") (optionOr (stringSlice l 0 (- (stringLength l) 1)) l) l)) (keepEnds (stringSplit t "\n") (list)))))
    ((err e) (err e)))

fn ! dropTmp! tmp: String e: String -> (Result Unit String)
  (let [(_ (pathRemove tmp))] (err e))

fn ! writeText! p: String text: String -> (Result Unit String)
  (let [(tmp (str p ".kit" (procSelf) ".tmp"))
        (mode (match (fileStat p) ((ok st) (some (mod st.mode 4096))) ((err _) (none))))]
    (match (fileWrite tmp text)
      ((err e) (dropTmp! tmp e))
      ((ok _)
        (match (match mode ((some m) (fileChmod tmp m)) ((none) (ok ())))
          ((err e) (dropTmp! tmp e))
          ((ok _)
            (match (fileFsync tmp)
              ((err e) (dropTmp! tmp e))
              ((ok _)
                (match (pathRename tmp p)
                  ((err e) (dropTmp! tmp e))
                  ((ok u) (ok u))))))))))

fn parentOf p: String -> String
  (match (listLast (stringSplit p "/"))
    ((some last) (if (= last p) "." (let [(d (optionOr (stringSlice p 0 (- (stringLength p) (+ (stringLength last) 1))) "."))] (if (stringEmpty? d) "/" d))))
    ((none) "."))

fn ! inside? k: Kit p: String -> Bool
  (match (realPath (if (fileExists? p) p (parentOf p)))
    ((ok rp) (or (= rp k.root) (stringStartsWith? rp (str k.root "/"))))
    ((err _) false))

fn replaceAll s: String from: String to: String -> String
  (stringReplace s from to)

fn sub pat: String s: String template: String -> (Result String String)
  (match (re/regex-compile! pat)
    ((ok r) (ok (re/regex-replace-all! r s template)))
    ((err e) (err (str "bad regex " (quote pat) ": " e))))

fn found? pat: String s: String -> (Result Bool String)
  (match (re/regex-compile! pat)
    ((ok r) (ok (re/regex-match? r s)))
    ((err e) (err (str "bad regex " (quote pat) ": " e))))

fn keepEnds parts: (List String) acc: (List String) -> (List String)
  (match (listHead parts)
    ((none) (listReverse acc))
    ((some h)
      (let [(rest (listDrop parts 1))]
        (if (listEmpty? rest)
          (keepEnds rest (if (stringEmpty? h) acc (cons h acc)))
          (keepEnds rest (cons (str h "\n") acc))))))

fn prefixLen a: (List String) b: (List String) n: Int64 -> Int64
  (match (listHead a)
    ((none) n)
    ((some x)
      (match (listHead b)
        ((none) n)
        ((some y) (if (= x y) (prefixLen (listDrop a 1) (listDrop b 1) (+ n 1)) n)))))

fn tagged tag: String xs: (List String) -> (List (Pair String String))
  (map (fn [(x String)] -> (Pair String String) (pair tag x)) xs)

fn flushRun dels: (List String) inss: (List String) acc: (List (Pair String String)) -> (List (Pair String String))
  (listAppend (listReverse (tagged "ins" (listReverse inss))) (listAppend (listReverse (tagged "del" (listReverse dels))) acc))

fn pairwise a: (List String) b: (List String) dels: (List String) inss: (List String) acc: (List (Pair String String)) -> (List (Pair String String))
  (match (listHead a)
    ((none) (listReverse (flushRun dels inss acc)))
    ((some x)
      (let [(y (optionOr (listHead b) ""))]
        (if (= x y)
          (pairwise (listDrop a 1) (listDrop b 1) (list) (list) (cons (pair "eq" x) (flushRun dels inss acc)))
          (pairwise (listDrop a 1) (listDrop b 1) (cons x dels) (cons y inss) acc)))))

fn middleOps a: (List String) b: (List String) -> (List (Pair String String))
  (if (= (listLength a) (listLength b))
    (pairwise a b (list) (list) (list))
    (listAppend (tagged "del" a) (tagged "ins" b)))

fn numberOps ops: (List (Pair String String)) ai: Int64 bi: Int64 acc: (List Op) -> (List Op)
  (match (listHead ops)
    ((none) (listReverse acc))
    ((some o)
      (let [(tag (pairFirst o))
            (op (Op :tag tag :text (pairSecond o) :ai ai :bi bi))
            (rest (listDrop ops 1))]
        (cond ((= tag "eq") (numberOps rest (+ ai 1) (+ bi 1) (cons op acc)))
              ((= tag "del") (numberOps rest (+ ai 1) bi (cons op acc)))
              (else (numberOps rest ai (+ bi 1) (cons op acc)))))))

fn ctxLines -> Int64
  3

fn hunkStep h: Hunks o: Op -> Hunks
  (if (= o.tag "eq")
    (if h.open
      (if (= h.trail (* 2 (ctxLines)))
        (Hunks :ctx (listTake (cons o h.cur) (ctxLines)) :cur (list) :open false :trail 0 :done (cons (listReverse (listDrop h.cur (ctxLines))) h.done))
        (with h :cur (cons o h.cur) :trail (+ h.trail 1)))
      (with h :ctx (listTake (cons o h.ctx) (ctxLines))))
    (if h.open
      (with h :cur (cons o h.cur) :trail 0)
      (with h :cur (cons o h.ctx) :ctx (list) :open true :trail 0)))

fn hunksOf ops: (List Op) -> (List (List Op))
  (let [(h (fold hunkStep (Hunks :ctx (list) :cur (list) :open false :trail 0 :done (list)) ops))]
    (listReverse (if h.open (cons (listReverse (listDrop h.cur (max 0 (- h.trail (ctxLines))))) h.done) h.done)))

fn opLine o: Op -> String
  (let [(mark (cond ((= o.tag "eq") " ") ((= o.tag "del") "-") (else "+")))]
    (if (stringEndsWith? o.text "\n")
      (str mark o.text)
      (str mark o.text "\n\\ No newline at end of file\n")))

fn range start: Int64 len: Int64 -> String
  (str (if (= len 0) (- start 1) start) "," len)

fn hunkText g: (List Op) -> String
  (let [(first (optionOr (listHead g) (Op :tag "eq" :text "" :ai 1 :bi 1)))
        (olds (listCount (fn [(o Op)] -> Bool (!= o.tag "ins")) g))
        (news (listCount (fn [(o Op)] -> Bool (!= o.tag "del")) g))]
    (str "@@ -" (range first.ai olds) " +" (range first.bi news) " @@\n" (stringJoin (map opLine g) "")))

fn diff path: String old: String new: String -> Diff
  (let [(a (keepEnds (stringSplit old "\n") (list)))
        (b (keepEnds (stringSplit new "\n") (list)))
        (p (prefixLen a b 0))
        (ra (listReverse (listDrop a p)))
        (rb (listReverse (listDrop b p)))
        (s (prefixLen ra rb 0))
        (midA (listReverse (listDrop ra s)))
        (midB (listReverse (listDrop rb s)))
        (ops (listAppend (tagged "eq" (listTake a p)) (listAppend (middleOps midA midB) (tagged "eq" (listReverse (listTake ra s))))))
        (groups (hunksOf (numberOps ops 1 1 (list))))]
    (Diff :text (if (listEmpty? groups) "" (str "--- a/" path "\n+++ b/" path "\n" (stringJoin (map hunkText groups) "")))
          :hunks (listLength groups)))

fn ! apply! k: Kit p: String old: String new: String -> (Result Unit String)
  (if (= old new)
    (do (println (str "(:skipped " (quote p) " :why \"unchanged\")")) (ok ()))
    (let [(d (diff p old new))]
      (if k.dry
        (do (print d.text) (println (str "(:wouldEdit " (quote p) " :hunks " d.hunks ")")) (ok ()))
        (match (writeText! p new)
          ((err e) (err (str p ": " e)))
          ((ok _) (do (println (str "(:edited " (quote p) " :hunks " d.hunks ")")) (ok ())))))))

fn ! edit! k: Kit p: String f: (fn [String] -> String) -> (Result Unit String)
  (if (and (not k.outside) (not (inside? k p)))
    (err (str "refusing to edit " p ": outside " k.root " (pass --allow-outside)"))
    (match (fileReadString p)
      ((err e) (err (str p ": " e)))
      ((ok old) (apply! k p old (f old)))))

fn ! editAll! k: Kit paths: (List String) f: (fn [String] -> String) -> (Result Unit String)
  (match (listHead paths)
    ((none) (ok ()))
    ((some p)
      (match (edit! k p f)
        ((err e) (err e))
        ((ok _) (editAll! k (listDrop paths 1) f)))))

fn ! editRx! k: Kit paths: (List String) pat: String template: String -> (Result Unit String)
  (match (re/regex-compile! pat)
    ((err e) (err (str "bad regex " (quote pat) ": " e)))
    ((ok r) (editAll! k paths (fn [(s String)] -> String (re/regex-replace-all! r s template)))))

fn ! shFor! secs: Int64 argv: (List String) -> Out
  (let [(o (fr/runGuarded argv "." (fr/childEnv (list)) (fr/limits secs 64)))]
    (Out :exit o.exitCode :out o.stdout :err o.stderr))

fn ! sh! argv: (List String) -> Out
  (shFor! 120 argv)
