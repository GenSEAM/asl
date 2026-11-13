(module aslBench/loop/core
  :x [Block Edit Half LoopTask Cfg Sandbox ToolOut Acc Verdict Trial Outcome RunState
      blocksOf bodyOf halfOf loadTask loadTasks allArms armKnown? armLang armRich? halfFor
      tagOf countOf pathOk? solvedOf itemStart? headerName itemRegion outlineOf renameWord cleanOut loadOf
      applyEdits! makeSandbox! sourceFiles! grade! toolStep! loopTrial! runAll! verifyTask!
      trialKey trialRow scriptCaller systemFor userFor costOf headerRow removeWork! pristineSha!]
  :i [(aslBench/gen/core :a gc) (asl-tools/fleet/run :a fr)])

; (:m :ref LOOPBENCH :do "whole-loop maintenance bench (asl/doc/loopBenchmark.md): one package in two languages, seeded tasks, a tool loop over a caller, hidden acceptance tests; a trial is solved only when the pristine suite, the hidden tests and the absent-text checks all pass on the sandbox the model left")

(schema Block
  (:f head (List String))
  (:f lines (List String)))

(schema Edit
  (:f file String)
  (:f old String)
  (:f new String)
  (:f all Bool))

(schema Half
  (:f prompt String)
  (:f seeds (List Edit))
  (:f refs (List Edit))
  (:f gradeEdits (List Edit))
  (:f accepts (List (Pair String String)))
  (:f absent (List String)))

(schema LoopTask
  (:f id String)
  (:f kind String)
  (:f asl Half)
  (:f py Half))

(schema Cfg
  (:f root String)
  (:f aslBin String)
  (:f work String)
  (:f out String)
  (:f maxTurns Int64)
  (:f maxTokens Int64)
  (:f trialTokens Int64)
  (:f resultClip Int64)
  (:f priceIn Int64)
  (:f priceOut Int64)
  (:f capPico Int64)
  (:f loadMax Int64)
  (:f loadWaitS Int64))

(schema Sandbox
  (:f lang String)
  (:f trial String)
  (:f pkg String)
  (:f pristine String))

(schema ToolOut
  (:f text String)
  (:f path String)
  (:f readLike Bool))

(schema Acc
  (:f turns Int64)
  (:f tokIn (List Int64))
  (:f tokOut (List Int64))
  (:f files (List String))
  (:f bytesRead Int64)
  (:f calls (List String))
  (:f stop String)
  (:f served String)
  (:f error String)
  (:f spent Int64))

(schema Verdict
  (:f suiteOk Bool)
  (:f acceptOk Bool)
  (:f absentOk Bool)
  (:f solved Bool)
  (:f detail String))

(schema Trial
  (:f arm String)
  (:f task LoopTask)
  (:f model String)
  (:f rep Int64))

(schema Outcome
  (:f trial Trial)
  (:f acc Acc)
  (:f verdict Verdict)
  (:f wallMs Int64))

(schema RunState
  (:f spent Int64)
  (:f done Int64)
  (:f skipped Int64)
  (:f stopped String))

fn allArms -> (List String)
  (list "py" "pyB" "aslA" "aslB")

fn armKnown? arm: String -> Bool
  (listContains? (allArms) arm)

fn armLang arm: String -> String
  (if (stringStartsWith? arm "py") "py" "asl")

fn armRich? arm: String -> Bool
  (stringEndsWith? arm "B")

fn halfFor t: LoopTask lang: String -> Half
  (if (= lang "py") t.py t.asl)

fn solvedOf suiteOk: Bool acceptOk: Bool absentOk: Bool -> Bool
  (and suiteOk acceptOk absentOk)

fn blockStep acc: (List Block) line: String -> (List Block)
  (if (stringStartsWith? line "#@ ")
    (cons (Block :head (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (gc/sliceFrom line 3) " ")) :lines (list)) acc)
    (match (listHead acc)
      ((none) acc)
      ((some b) (cons (Block :head b.head :lines (cons line b.lines)) (optionOr (listTail acc) (list))))))

fn dropBlank ls: (List String) -> (List String)
  (match (listHead ls)
    ((none) ls)
    ((some l) (if (stringEmpty? (stringTrim l)) (dropBlank (optionOr (listTail ls) (list))) ls)))

fn bodyOf b: Block -> String
  (stringJoin (listReverse (dropBlank b.lines)) "\n")

fn blocksOf text: String -> (List Block)
  (listReverse (fold blockStep (list) (stringLines text)))

fn headAt b: Block i: Int64 -> String
  (optionOr (listGet b.head i) "")

fn blocksNamed blocks: (List Block) kind: String -> (List Block)
  (filter (fn [(b Block)] -> Bool (= (headAt b 0) kind)) blocks)

fn editAt blocks: (List Block) kind: String i: Int64 -> (List Edit)
  (match (listGet blocks i)
    ((none) (list))
    ((some b)
      (let [(k (headAt b 0))
            (whole (= k (str kind "All")))]
        (if (or (= k kind) whole)
          (list (Edit :file (headAt b 1) :old (bodyOf b)
                      :new (match (listGet blocks (+ i 1))
                             ((some w) (if (= (headAt w 0) "with") (bodyOf w) ""))
                             ((none) ""))
                      :all whole))
          (list)))))

fn editsOf blocks: (List Block) kind: String -> (List Edit)
  (listFlatMap (fn [(i Int64)] -> (List Edit) (editAt blocks kind i)) (range 0 (listLength blocks)))

fn halfOf blocks: (List Block) -> Half
  (Half :prompt (match (listHead (blocksNamed blocks "prompt")) ((some b) (bodyOf b)) ((none) ""))
        :seeds (editsOf blocks "seed")
        :refs (editsOf blocks "ref")
        :gradeEdits (editsOf blocks "gradeEdit")
        :accepts (map (fn [(b Block)] -> (Pair String String) (pair (headAt b 1) (str (bodyOf b) "\n"))) (blocksNamed blocks "accept"))
        :absent (map bodyOf (blocksNamed blocks "absent")))

fn emptyHalf -> Half
  (Half :prompt "" :seeds (list) :refs (list) :gradeEdits (list) :accepts (list) :absent (list))

fn ! loadTask root: String id: String -> (Result LoopTask String)
  (match (fileReadString (str root "/asl/bench/loop/tasks/" id ".task"))
    ((err e) (err e))
    ((ok aslText)
      (let [(blocks (blocksOf aslText))
            (top (optionOr (listHead (blocksNamed blocks "task")) (Block :head (list) :lines (list))))
            (pyHalf (match (fileReadString (str root "/asl/bench/loop/py/tasks/" id ".task"))
                      ((ok t) (halfOf (blocksOf t)))
                      ((err _) (emptyHalf))))]
        (if (!= (headAt top 1) id)
          (err (str "task file " id ".task does not open with #@ task " id " KIND"))
          (ok (LoopTask :id id :kind (headAt top 2) :asl (halfOf blocks) :py pyHalf))))))

fn ! loadTasks root: String -> (Result (List LoopTask) String)
  (match (dirList (str root "/asl/bench/loop/tasks"))
    ((err e) (err e))
    ((ok names)
      (fold (fn [(acc (Result (List LoopTask) String)) (name String)] -> (Result (List LoopTask) String)
              (match acc
                ((err e) (err e))
                ((ok ts)
                  (if (stringEndsWith? name ".task")
                    (match (loadTask root (gc/slice name 0 (- (stringLength name) 5)))
                      ((err e) (err e))
                      ((ok t) (ok (listAppend ts (list t)))))
                    (ok ts)))))
            (ok (list))
            names)))

fn trimNl s: String -> String
  (let [(a (if (stringStartsWith? s "\n") (gc/sliceFrom s 1) s))]
    (if (stringEndsWith? a "\n") (gc/slice a 0 (- (stringLength a) 1)) a))

fn tagOf text: String tag: String -> (Option String)
  (let [(open (str "<" tag ">"))]
    (match (stringIndexOf text open)
      ((none) (none))
      ((some i)
        (let [(rest (gc/sliceFrom text (+ i (stringLength open))))]
          (match (stringIndexOf rest (str "</" tag ">"))
            ((none) (none))
            ((some j) (some (trimNl (gc/slice rest 0 j)))))))))

fn argOf reply: String tag: String -> String
  (optionOr (tagOf reply tag) "")

fn countOf text: String needle: String -> Int64
  (if (stringEmpty? needle) 0 (- (listLength (stringSplit text needle)) 1))

fn pathOk? p: String -> Bool
  (and (not (stringEmpty? p)) (not (stringStartsWith? p "/")) (not (stringContains? p "..")) (not (stringContains? p "\n")))

fn srcDirOf lang: String -> String
  (if (= lang "py") "stats" "src")

fn extOf lang: String -> String
  (if (= lang "py") ".py" ".asl")

fn pkgSub lang: String -> String
  (if (= lang "py") "" "/asl/packages/asl-stats")

fn pristineOf root: String lang: String -> String
  (if (= lang "py") (str root "/asl/bench/loop/py") (str root "/asl/packages/asl-stats"))

fn ! namesIn dir: String ext: String -> (List String)
  (filter (fn [(n String)] -> Bool (stringEndsWith? n ext)) (resultOr (dirList dir) (list)))

fn ! copyDir! from: String to: String sub: String ext: String -> Int64
  (let [(made (dirCreate (str to "/" sub)))]
    (listSum (map (fn [(n String)] -> Int64
                    (match (fileReadString (str from "/" sub "/" n))
                      ((err _) 0)
                      ((ok text) (if (ok? (fileWrite (str to "/" sub "/" n) text)) 1 0))))
                  (namesIn (str from "/" sub) ext))))

fn ! sourceFiles! sb: Sandbox -> (List String)
  (listFlatMap (fn [(d String)] -> (List String) (map (fn [(n String)] -> String (str d "/" n)) (namesIn (str sb.pkg "/" d) (extOf sb.lang))))
               (list (srcDirOf sb.lang) "tests"))

fn ! applyEdit! pkg: String e: Edit -> (Result Int64 String)
  (let [(path (str pkg "/" e.file))
        (text (resultOr (fileReadString path) ""))
        (n (countOf text e.old))]
    (cond
      ((not (pathOk? e.file)) (err (str "the path must be relative to the package root, without ..: " e.file)))
      ((stringEmpty? e.old)
        (match (fileWrite path (str text e.new "\n"))
          ((err x) (err x))
          ((ok _) (ok 1))))
      ((= n 0) (err (str e.file ": the old text does not occur in the file; it must match exactly, including indentation")))
      ((and (> n 1) (not e.all)) (err (str e.file ": the old text occurs " (stringFromInt64 n) " times; add surrounding lines until it is unique")))
      (else
        (match (fileWrite path (stringReplace text e.old e.new))
          ((err x) (err x))
          ((ok _) (ok n))))))

fn ! applyEdits! pkg: String edits: (List Edit) -> (Result Int64 String)
  (fold (fn [(acc (Result Int64 String)) (e Edit)] -> (Result Int64 String)
          (match acc
            ((err x) (err x))
            ((ok n)
              (match (applyEdit! pkg e)
                ((err x) (err x))
                ((ok k) (ok (+ n k)))))))
        (ok 0)
        edits)

fn safeKey key: String -> String
  (stringReplace (stringReplace key "|" "-") "/" "-")

fn ! makeSandbox! cfg: Cfg lang: String key: String half: Half -> (Result Sandbox String)
  (let [(trial (str cfg.work "/t-" (safeKey key)))
        (pkg (str trial (pkgSub lang)))
        (pristine (pristineOf cfg.root lang))
        (made (dirCreate pkg))
        (conf (if (= lang "asl")
                (and (ok? (fileWrite (str trial "/.asl.config.asn") "(:aslConfig :workspace \"aslLoopBenchSandbox\")\n"))
                     (ok? (fileWrite (str pkg "/manifest.asn") (resultOr (fileReadString (str pristine "/manifest.asn")) ""))))
                true))
        (nSrc (copyDir! pristine pkg (srcDirOf lang) (extOf lang)))
        (nTests (copyDir! pristine pkg "tests" (extOf lang)))
        (sb (Sandbox :lang lang :trial trial :pkg pkg :pristine pristine))]
    (cond
      ((not (stringContains? cfg.work "aslLoopBench")) (err "the work directory name must contain aslLoopBench"))
      ((or (< nSrc 1) (< nTests 1)) (err (str "no pristine sources under " pristine)))
      ((not conf) (err (str "cannot write the sandbox config under " trial)))
      (else
        (match (applyEdits! pkg half.seeds)
          ((err e) (err (str "seed: " e)))
          ((ok _) (ok sb))))))

fn loadOf text: String -> Int64
  (let [(words (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringReplace (stringTrim text) "," " ") " ")))
        (w (optionOr (listGet words (- (listLength words) 3)) "0"))]
    (optionOr (stringToInt64 (optionOr (listHead (stringSplit w ".")) "0")) 0))

fn ! waitLoad! cfg: Cfg waited: Int64 -> Int64
  (let [(d (fr/runOneLimited (fr/job (list "uptime") "/" (fr/childEnv (list))) (fr/limits 20 2)))]
    (if (or (<= (loadOf d.out) cfg.loadMax) (>= waited cfg.loadWaitS))
      waited
      (do (sleepMs 15000) (waitLoad! cfg (+ waited 15)))))

fn ! gate! cfg: Cfg -> Int64
  (if (>= cfg.loadMax 1000) 0 (waitLoad! cfg 0))

fn ! child! cfg: Cfg argv: (List String) dir: String env: (List String) timeoutS: Int64 -> fr/Done
  (let [(waited (gate! cfg))]
    (fr/runOneLimited (fr/job (listAppend (list "nice" "-n" "10") argv) dir env) (fr/limits timeoutS 16)))

fn stripAbs line: String -> String
  (if (stringStartsWith? line "/")
    (match (stringIndexOf line "/asl/packages/asl-stats/")
      ((some i) (gc/sliceFrom line (+ i 24)))
      ((none) line))
    line)

fn stripCache word: String -> String
  (match (stringIndexOf word "aslLoopBenchSandbox/")
    ((some i) (gc/sliceFrom word (+ i 20)))
    ((none) word))

fn noise? line: String -> Bool
  (or (stringContains? line "RequestsDependencyWarning") (= (stringTrim line) "warnings.warn("))

fn cleanOut sb: Sandbox out: String -> String
  (let [(a (stringReplace (stringReplace out (str sb.pkg "/") "") (str sb.trial "/") ""))
        (ls (map (fn [(l String)] -> String (stringJoin (map stripCache (stringSplit (stripAbs l) " ")) " "))
                 (filter (fn [(l String)] -> Bool (not (noise? l))) (stringLines a))))]
    (stringReplace (stringJoin ls "\n") "asl/packages/asl-stats/" ""))

fn tailClip text: String n: Int64 -> String
  (let [(len (stringLength text))]
    (if (> len n) (str "[" (stringFromInt64 (- len n)) " earlier characters cut]\n" (gc/sliceFrom text (- len n))) text))

fn ! runTests! cfg: Cfg sb: Sandbox files: (List String) -> (Pair Bool String)
  (if (= sb.lang "py")
    (let [(d (child! cfg (listAppend (list "python3" "-m" "pytest" "-q" "-x" "--no-header" "-p" "no:cacheprovider") files) sb.pkg
                     (fr/childEnv (list "PYTHONDONTWRITEBYTECODE=1")) 180))]
      (pair (= d.exit 0) (cleanOut sb d.out)))
    (fold (fn [(acc (Pair Bool String)) (f String)] -> (Pair Bool String)
            (if (not (pairFirst acc))
              acc
              (let [(d (child! cfg (list cfg.aslBin "test" (str "asl/packages/asl-stats/" f)) sb.trial (fr/childEnv (list (str "ASL_ROOT=" sb.trial))) 180))]
                (pair (= d.exit 0) (str (pairSecond acc) (cleanOut sb d.out) "\n")))))
          (pair true "")
          files))

fn ! runCheck! cfg: Cfg sb: Sandbox files: (List String) -> (Pair Bool String)
  (if (= sb.lang "py")
    (let [(d (child! cfg (listAppend (list "python3" "-m" "mypy" "--strict" "--no-incremental") files) sb.pkg (fr/childEnv (list)) 180))]
      (pair (= d.exit 0) (cleanOut sb d.out)))
    (let [(d (child! cfg (listAppend (list cfg.aslBin "check") (map (fn [(f String)] -> String (str "asl/packages/asl-stats/" f)) files)) sb.trial
                     (fr/childEnv (list (str "ASL_ROOT=" sb.trial))) 180))]
      (pair (and (= d.exit 0) (not (stringContains? d.out ":status :failed"))) (cleanOut sb d.out))))

fn ! testFiles! sb: Sandbox -> (List String)
  (filter (fn [(f String)] -> Bool (stringStartsWith? f "tests/")) (sourceFiles! sb))

fn checkTargets sb: Sandbox files: (List String) -> (List String)
  (if (= sb.lang "py") (list "stats" "tests") files)

fn itemStart? line: String -> Bool
  (and (not (stringEmpty? line)) (not (stringContains? " \t)]}" (gc/charAt line 0))))

fn skipWord? w: String -> Bool
  (listContains? (list "fn" "!" "def" "class" "schema" "(schema" "enum" "(enum" "async" "tailrec" "(module") w)

fn nameCut w: String -> String
  (gc/slice w 0 (fold (fn [(m Int64) (c String)] -> Int64 (match (stringIndexOf w c) ((some i) (min m i)) ((none) m)))
                      (stringLength w)
                      (list "(" ":" "=" "[")))

fn headerName line: String -> String
  (nameCut (optionOr (listHead (filter (fn [(w String)] -> Bool (and (not (stringEmpty? w)) (not (skipWord? w)))) (stringSplit line " "))) ""))

fn tailrec findFrom lines: (List String) i: Int64 pred: (fn [String] -> Bool) -> Int64
  (match (listGet lines i)
    ((none) i)
    ((some l) (if (pred l) i (findFrom lines (+ i 1) pred))))

fn tailrec backBlank lines: (List String) e: Int64 lo: Int64 -> Int64
  (if (<= e lo)
    e
    (if (stringEmpty? (stringTrim (optionOr (listGet lines (- e 1)) ""))) (backBlank lines (- e 1) lo) e))

fn itemRegion lines: (List String) name: String -> (Option (Pair Int64 Int64))
  (let [(start (findFrom lines 0 (fn [(l String)] -> Bool (and (itemStart? l) (= (headerName l) name)))))]
    (if (>= start (listLength lines))
      (none)
      (some (pair start (backBlank lines (findFrom lines (+ start 1) itemStart?) (+ start 1))))))

fn itemNames lines: (List String) -> (List String)
  (map headerName (filter (fn [(l String)] -> Bool (and (itemStart? l) (not (stringStartsWith? l ";")) (not (stringStartsWith? l "#")))) lines))

fn outlineOf text: String -> String
  (let [(lines (stringLines text))]
    (stringJoin
      (listFlatMap (fn [(p (Pair Int64 String))] -> (List String)
                     (let [(l (pairSecond p))]
                       (if (or (and (itemStart? l) (not (stringStartsWith? l ";")) (not (stringStartsWith? l "#")))
                               (or (stringStartsWith? l "  :x") (stringStartsWith? l "  :i")))
                         (list (str (stringFromInt64 (pairFirst p)) ": " (gc/clip l 200)))
                         (list))))
                   (zip (range 1 (+ (listLength lines) 1)) lines))
      "\n"))

fn identChar? c: String -> Bool
  (and (not (stringEmpty? c)) (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_?!" c))

fn lastChar s: String -> String
  (if (stringEmpty? s) "" (gc/charAt s (- (stringLength s) 1)))

fn renameWord text: String old: String new: String -> (Pair String Int64)
  (let [(parts (stringSplit text old))]
    (fold (fn [(acc (Pair String Int64)) (i Int64)] -> (Pair String Int64)
            (let [(part (optionOr (listGet parts i) ""))
                  (word? (and (not (identChar? (lastChar (optionOr (listGet parts (- i 1)) ""))))
                              (not (identChar? (gc/charAt part 0)))))]
              (pair (str (pairFirst acc) (if word? new old) part) (+ (pairSecond acc) (if word? 1 0)))))
          (pair (optionOr (listHead parts) "") 0)
          (range 1 (listLength parts))))

fn out text: String -> ToolOut
  (ToolOut :text text :path "" :readLike false)

fn seen text: String path: String -> ToolOut
  (ToolOut :text text :path path :readLike true)

fn ! toolRead! sb: Sandbox reply: String -> ToolOut
  (let [(path (argOf reply "path"))]
    (if (not (pathOk? path))
      (out "ERR read needs <path>, relative to the package root")
      (match (fileReadString (str sb.pkg "/" path))
        ((err _) (out (str "ERR no such file: " path "; files: " (stringJoin (sourceFiles! sb) " "))))
        ((ok text)
          (let [(lines (stringLines text))
                (total (listLength lines))
                (from (max 1 (optionOr (stringToInt64 (stringTrim (argOf reply "from"))) 1)))
                (to (min total (optionOr (stringToInt64 (stringTrim (argOf reply "to"))) (+ from 399))))
                (part (listTake (listDrop lines (- from 1)) (max 0 (+ (- to from) 1))))]
            (seen (str (stringJoin part "\n")
                       (if (or (> from 1) (< to total))
                         (str "\n[lines " (stringFromInt64 from) "-" (stringFromInt64 to) " of " (stringFromInt64 total) "]")
                         ""))
                  path))))))

fn ! grepFile! sb: Sandbox file: String pattern: String -> (List String)
  (let [(lines (stringLines (resultOr (fileReadString (str sb.pkg "/" file)) "")))]
    (listFlatMap (fn [(p (Pair Int64 String))] -> (List String)
                   (if (stringContains? (pairSecond p) pattern)
                     (list (str file ":" (stringFromInt64 (pairFirst p)) ": " (gc/clip (stringTrim (pairSecond p)) 200)))
                     (list)))
                 (zip (range 1 (+ (listLength lines) 1)) lines)))

fn ! toolGrep! sb: Sandbox reply: String -> ToolOut
  (let [(pattern (argOf reply "pattern"))
        (path (argOf reply "path"))
        (files (if (stringEmpty? path) (sourceFiles! sb) (filter (fn [(f String)] -> Bool (stringStartsWith? f path)) (sourceFiles! sb))))
        (hits (listFlatMap (fn [(f String)] -> (List String) (grepFile! sb f pattern)) files))]
    (cond
      ((stringEmpty? pattern) (out "ERR grep needs <pattern>, a literal substring"))
      ((listEmpty? hits) (seen (str "no line contains " pattern) ""))
      (else (seen (str (stringJoin (listTake hits 80) "\n")
                       (if (> (listLength hits) 80) (str "\n[" (stringFromInt64 (listLength hits)) " hits, first 80 shown]") ""))
                  ""))))

fn ! toolEdit! sb: Sandbox reply: String -> ToolOut
  (let [(path (argOf reply "path"))
        (old (argOf reply "old"))]
    (cond
      ((or (stringEmpty? old) (none? (tagOf reply "new"))) (out "ERR edit needs <path>, <old> and <new>; old must be non-empty"))
      ((not (fileExists? (str sb.pkg "/" path))) (out (str "ERR no such file: " path)))
      (else
        (match (applyEdit! sb.pkg (Edit :file path :old old :new (argOf reply "new") :all false))
          ((err e) (out (str "ERR " e)))
          ((ok _) (out (str "edited " path)))))))

fn ! toolWrite! sb: Sandbox reply: String -> ToolOut
  (let [(path (argOf reply "path"))]
    (cond
      ((or (not (pathOk? path)) (none? (tagOf reply "text"))) (out "ERR write needs <path> and <text>"))
      ((not (or (stringStartsWith? path (str (srcDirOf sb.lang) "/")) (stringStartsWith? path "tests/"))) (out (str "ERR files live under " (srcDirOf sb.lang) "/ or tests/")))
      (else
        (match (fileWrite (str sb.pkg "/" path) (str (argOf reply "text") "\n"))
          ((err e) (out (str "ERR " e)))
          ((ok _) (out (str "wrote " path)))))))

fn ! toolTest! cfg: Cfg sb: Sandbox reply: String -> ToolOut
  (let [(path (argOf reply "path"))
        (files (if (stringEmpty? path) (testFiles! sb) (list path)))]
    (if (and (not (stringEmpty? path)) (not (and (pathOk? path) (fileExists? (str sb.pkg "/" path)))))
      (out (str "ERR no such test file: " path))
      (let [(r (runTests! cfg sb (if (and (= sb.lang "py") (stringEmpty? path)) (list "tests") files)))]
        (out (str (if (pairFirst r) "PASS\n" "FAIL\n") (tailClip (pairSecond r) 3000))))))

fn ! toolCheck! cfg: Cfg sb: Sandbox reply: String -> ToolOut
  (let [(path (argOf reply "path"))
        (files (if (stringEmpty? path) (checkTargets sb (sourceFiles! sb)) (list path)))]
    (if (and (not (stringEmpty? path)) (not (and (pathOk? path) (fileExists? (str sb.pkg "/" path)))))
      (out (str "ERR no such file: " path))
      (let [(r (runCheck! cfg sb files))]
        (out (str (if (pairFirst r) "CHECK OK\n" "CHECK FAILED\n") (tailClip (pairSecond r) 3000))))))

fn ! toolOutline! sb: Sandbox reply: String -> ToolOut
  (let [(path (argOf reply "path"))]
    (match (if (pathOk? path) (fileReadString (str sb.pkg "/" path)) (err "path"))
      ((err _) (out (str "ERR no such file: " path "; files: " (stringJoin (sourceFiles! sb) " "))))
      ((ok text) (seen (outlineOf text) path))))

fn ! toolSymbol! sb: Sandbox reply: String -> ToolOut
  (let [(path (argOf reply "path"))
        (name (stringTrim (argOf reply "name")))]
    (match (if (pathOk? path) (fileReadString (str sb.pkg "/" path)) (err "path"))
      ((err _) (out (str "ERR no such file: " path "; files: " (stringJoin (sourceFiles! sb) " "))))
      ((ok text)
        (let [(lines (stringLines text))]
          (match (itemRegion lines name)
            ((none) (out (str "ERR no top-level item named " name " in " path "; items: " (stringJoin (itemNames lines) " "))))
            ((some r)
              (seen (str "[" path " lines " (stringFromInt64 (+ (pairFirst r) 1)) "-" (stringFromInt64 (pairSecond r)) "]\n"
                         (stringJoin (listTake (listDrop lines (pairFirst r)) (- (pairSecond r) (pairFirst r))) "\n"))
                    path)))))))

fn ! toolReplace! cfg: Cfg sb: Sandbox reply: String -> ToolOut
  (let [(path (argOf reply "path"))
        (name (stringTrim (argOf reply "name")))
        (body (argOf reply "body"))]
    (match (if (and (pathOk? path) (not (stringEmpty? body))) (fileReadString (str sb.pkg "/" path)) (err "args"))
      ((err _) (out "ERR replace needs <path> of an existing file, <name> and a non-empty <body>"))
      ((ok text)
        (let [(lines (stringLines text))]
          (match (itemRegion lines name)
            ((none) (out (str "ERR no top-level item named " name " in " path "; items: " (stringJoin (itemNames lines) " "))))
            ((some r)
              (match (fileWrite (str sb.pkg "/" path)
                                (stringJoin (listAppend (listTake lines (pairFirst r)) (listAppend (stringLines body) (listDrop lines (pairSecond r)))) "\n"))
                ((err e) (out (str "ERR " e)))
                ((ok _)
                  (let [(c (runCheck! cfg sb (checkTargets sb (list path))))]
                    (out (str "replaced " name " in " path "; " (if (pairFirst c) "CHECK OK" (str "CHECK FAILED\n" (tailClip (pairSecond c) 2500))))))))))))))

fn ! toolRename! cfg: Cfg sb: Sandbox reply: String -> ToolOut
  (let [(old (stringTrim (argOf reply "old")))
        (new (stringTrim (argOf reply "new")))
        (files (sourceFiles! sb))
        (counts (map (fn [(f String)] -> (Pair String Int64)
                       (let [(text (resultOr (fileReadString (str sb.pkg "/" f)) ""))
                             (r (renameWord text old new))
                             (wrote (if (> (pairSecond r) 0) (ok? (fileWrite (str sb.pkg "/" f) (pairFirst r))) true))]
                         (pair f (pairSecond r))))
                     (if (or (stringEmpty? old) (stringEmpty? new)) (list) files)))
        (hit (filter (fn [(p (Pair String Int64))] -> Bool (> (pairSecond p) 0)) counts))]
    (cond
      ((or (stringEmpty? old) (stringEmpty? new)) (out "ERR rename needs <old> and <new>"))
      ((listEmpty? hit) (out (str "ERR the identifier " old " occurs in no file")))
      (else
        (let [(c (runCheck! cfg sb (checkTargets sb files)))]
          (out (str "renamed " old " to " new ": "
                    (stringJoin (map (fn [(p (Pair String Int64))] -> String (str (pairFirst p) " " (stringFromInt64 (pairSecond p)))) hit) ", ")
                    "; " (if (pairFirst c) "CHECK OK" (str "CHECK FAILED\n" (tailClip (pairSecond c) 2500)))))))))

fn ! toolLens! cfg: Cfg sb: Sandbox reply: String -> ToolOut
  (let [(path (argOf reply "path"))
        (name (stringTrim (argOf reply "name")))]
    (if (not (and (pathOk? path) (fileExists? (str sb.pkg "/" path))))
      (out (str "ERR no such file: " path))
      (let [(d (child! cfg (listAppend (list cfg.aslBin "run" (str cfg.root "/tools/typeLens/typeLens.asl") (str "asl/packages/asl-stats/" path))
                                       (if (stringEmpty? name) (list) (list "--symbol" name)))
                       sb.trial (fr/childEnv (list (str "ASL_ROOT=" sb.trial))) 240))]
        (if (and (= d.exit 0) (stringContains? d.out "(:lens"))
          (seen (cleanOut sb d.out) path)
          (out (str "ERR lens: " (tailClip (cleanOut sb d.out) 1500)))))))

fn ! toolCard! cfg: Cfg -> ToolOut
  (seen (optionOr (listHead (stringLines (resultOr (fileReadString (str cfg.root "/asl/packages/asl-know/cards/asl-stats.asn")) "ERR no card"))) "") "card")

fn plainTools -> (List String)
  (list "read" "grep" "edit" "write" "test" "check")

fn richTools -> (List String)
  (list "outline" "symbol" "replace" "rename")

fn toolsOf arm: String -> (List String)
  (listAppend (plainTools) (if (armRich? arm) (listAppend (richTools) (if (= arm "aslB") (list "lens" "card") (list))) (list)))

fn ! toolStep! cfg: Cfg sb: Sandbox arm: String tool: String reply: String -> ToolOut
  (cond
    ((not (listContains? (toolsOf arm) tool))
      (out (str "ERR " (if (stringEmpty? tool) "the reply holds no <tool>NAME</tool> call" (str "unknown tool " tool))
                "; tools: " (stringJoin (toolsOf arm) " ") " done")))
    ((= tool "read") (toolRead! sb reply))
    ((= tool "grep") (toolGrep! sb reply))
    ((= tool "edit") (toolEdit! sb reply))
    ((= tool "write") (toolWrite! sb reply))
    ((= tool "test") (toolTest! cfg sb reply))
    ((= tool "check") (toolCheck! cfg sb reply))
    ((= tool "outline") (toolOutline! sb reply))
    ((= tool "symbol") (toolSymbol! sb reply))
    ((= tool "replace") (toolReplace! cfg sb reply))
    ((= tool "rename") (toolRename! cfg sb reply))
    ((= tool "lens") (toolLens! cfg sb reply))
    (else (toolCard! cfg)))

fn toolLine arm: String tool: String -> String
  (let [(py (= (armLang arm) "py"))]
    (cond
      ((= tool "read") "read: <path>, optional <from> and <to> (1-based line numbers). Returns the file text, at most 400 lines per call.")
      ((= tool "grep") "grep: <pattern> (a literal substring), optional <path> prefix. Returns path:line: text for every matching line.")
      ((= tool "edit") "edit: <path> <old> <new>. Replaces the one exact occurrence of old with new; old must occur exactly once.")
      ((= tool "write") "write: <path> <text>. Creates or overwrites a file.")
      ((= tool "test") (if py "test: optional <path>. Runs pytest on one test file or on the whole suite."
                             "test: optional <path>. Runs asl test on one test file or on every test file."))
      ((= tool "check") (if py "check: runs mypy --strict on the package and its tests."
                              "check: optional <path>. Runs asl check, the static checker, on one file or on every file."))
      ((= tool "outline") "outline: <path>. The top-level items of a file, one header line each, with line numbers.")
      ((= tool "symbol") "symbol: <path> <name>. The source of one top-level definition.")
      ((= tool "replace") "replace: <path> <name> <body>. Replaces one whole top-level definition with body, then runs the checker and returns its verdict.")
      ((= tool "rename") "rename: <old> <new>. Renames an identifier, whole words only, in every source and test file, then runs the checker.")
      ((= tool "lens") "lens: <path> <name>. One definition with its compile-time facts: its signature and effect, and the signature of every symbol it uses, imported ones included.")
      (else "card: the package card: purpose, modules and exported signatures.")))

fn ! systemFor cfg: Cfg arm: String -> String
  (str "You maintain a small software package through tools. Every reply holds exactly one tool call written as tags, optionally after one short line of reasoning:\n"
       "<tool>NAME</tool>\n<path>value</path>\n"
       "Each argument is its own tag, named exactly as in the tool list below (a path is always <path>, never the tool's name), and multi-line values go between the tags as they are. The result arrives in the next message. "
       "Paths are relative to the package root. When the task is complete reply <tool>done</tool>; the package is then graded by hidden tests and the existing suite. "
       "You have at most " (stringFromInt64 cfg.maxTurns) " replies, so read only what you need.\n\nTools:\n"
       (stringJoin (map (fn [(t String)] -> String (toolLine arm t)) (toolsOf arm)) "\n")
       "\ndone: no arguments.\n\n"
       (if (= (armLang arm) "py")
         "The package is Python 3.13 with type hints, standard library only, tested with pytest."
         (stringTrim (resultOr (fileReadString (str cfg.root "/asl/bench/loop/cards/asl.txt")) ""))))

fn ! userFor sb: Sandbox half: Half -> String
  (str half.prompt "\n\nFiles:\n"
       (stringJoin (map (fn [(f String)] -> String
                          (str f " (" (stringFromInt64 (listLength (stringLines (resultOr (fileReadString (str sb.pkg "/" f)) "")))) " lines)"))
                        (sourceFiles! sb))
                   "\n"))

fn costOf cfg: Cfg tokIn: Int64 tokOut: Int64 -> Int64
  (+ (* tokIn cfg.priceIn) (* tokOut cfg.priceOut))

fn callLabel tool: String reply: String -> String
  (stringTrim (str tool " " (argOf reply "path") (if (stringEmpty? (argOf reply "name")) "" (str "#" (stringTrim (argOf reply "name"))))))

fn clipResult cfg: Cfg text: String -> String
  (if (> (stringLength text) cfg.resultClip)
    (str (gc/slice text 0 cfg.resultClip) "\n[" (stringFromInt64 (- (stringLength text) cfg.resultClip)) " more characters cut]")
    text)

fn accReply acc: Acc turn: Int64 rep: gc/Reply cost: Int64 -> Acc
  (with acc :turns turn :tokIn (listAppend acc.tokIn (list rep.tokIn)) :tokOut (listAppend acc.tokOut (list rep.tokOut))
            :spent (+ acc.spent cost) :served rep.served)

fn accStop acc: Acc stop: String error: String -> Acc
  (with acc :stop stop :error error)

fn accCall acc: Acc label: String -> Acc
  (with acc :calls (listAppend acc.calls (list label)))

fn accTool acc: Acc label: String o: ToolOut shown: String -> Acc
  (with acc :calls (listAppend acc.calls (list label))
            :files (if (and o.readLike (not (stringEmpty? o.path)) (not (listContains? acc.files o.path)))
                     (listAppend acc.files (list o.path))
                     acc.files)
            :bytesRead (+ acc.bytesRead (if o.readLike (stringLength shown) 0)))

fn ! turnLoop! cfg: Cfg tr: Trial sb: Sandbox system: String messages: (List (Pair String String)) turn: Int64 call: (fn [S gc/Req] -> (Pair S gc/Reply)) state: S acc: Acc -> (Pair S Acc)
  (let [(req (gc/Req :model tr.model :arm tr.arm :task tr.task.id :rep tr.rep :turn turn :system system :messages messages :maxTokens cfg.maxTokens))]
    (cond
      ((> turn cfg.maxTurns) (pair state (accStop acc "turns" "")))
      ((> (+ (listSum acc.tokIn) (listSum acc.tokOut)) cfg.trialTokens) (pair state (accStop acc "tokens" "")))
      ((> (+ acc.spent (costOf cfg (/ (gc/reqChars req) 2) cfg.maxTokens)) cfg.capPico) (pair state (accStop acc "budget" "")))
      (else
        (let [(res (call state req))
              (state2 (pairFirst res))
              (rep (pairSecond res))
              (acc2 (accReply acc turn rep (costOf cfg rep.tokIn rep.tokOut)))
              (tool (stringTrim (argOf rep.text "tool")))]
          (cond
            ((not (stringEmpty? rep.error)) (pair state2 (accStop acc2 "call" rep.error)))
            ((= tool "done") (pair state2 (accStop (accCall acc2 "done") "done" "")))
            (else
              (let [(o (toolStep! cfg sb tr.arm tool rep.text))
                    (shown (clipResult cfg o.text))
                    (logged (fileAppend (str sb.trial ".log") (str "=== turn " (stringFromInt64 turn) " reply\n" rep.text "\n=== result\n" shown "\n")))
                    (acc3 (accTool acc2 (callLabel tool rep.text) o shown))]
                (turnLoop! cfg tr sb system
                           (listAppend messages (list (pair "assistant" rep.text) (pair "user" (str "RESULT\n" shown))))
                           (+ turn 1) call state2 acc3))))))))

fn ! absentOk! sb: Sandbox texts: (List String) -> Bool
  (let [(srcs (filter (fn [(f String)] -> Bool (not (stringStartsWith? f "tests/"))) (sourceFiles! sb)))
        (all (stringJoin (map (fn [(f String)] -> String (resultOr (fileReadString (str sb.pkg "/" f)) "")) srcs) "\n"))]
    (listAll? (fn [(t String)] -> Bool (or (stringEmpty? t) (not (stringContains? all t)))) texts))

fn ! grade! cfg: Cfg sb: Sandbox half: Half -> Verdict
  (let [(restored (copyDir! sb.pristine sb.pkg "tests" (extOf sb.lang)))
        (pristineTests (map (fn [(n String)] -> String (str "tests/" n)) (namesIn (str sb.pristine "/tests") (extOf sb.lang))))
        (patched (applyEdits! sb.pkg half.gradeEdits))
        (wrote (listAll? (fn [(p (Pair String String))] -> Bool (ok? (fileWrite (str sb.pkg "/" (pairFirst p)) (pairSecond p)))) half.accepts))
        (suite (if (and (ok? patched) wrote) (runTests! cfg sb pristineTests) (pair false "the grading edits or the acceptance files could not be written")))
        (accept (if (listEmpty? half.accepts) (pair true "") (runTests! cfg sb (map pairFirst half.accepts))))
        (absent (absentOk! sb half.absent))]
    (Verdict :suiteOk (pairFirst suite) :acceptOk (pairFirst accept) :absentOk absent
             :solved (solvedOf (pairFirst suite) (pairFirst accept) absent)
             :detail (gc/clip (str (if (pairFirst suite) "" (tailClip (pairSecond suite) 600)) (if (pairFirst accept) "" (tailClip (pairSecond accept) 600))) 1400)))

fn emptyAcc spent: Int64 -> Acc
  (Acc :turns 0 :tokIn (list) :tokOut (list) :files (list) :bytesRead 0 :calls (list) :stop "" :served "" :error "" :spent spent)

fn trialKey tr: Trial -> String
  (str tr.arm "|" tr.task.id "|" tr.model "|" (stringFromInt64 tr.rep))

fn ! loopTrial! cfg: Cfg tr: Trial call: (fn [S gc/Req] -> (Pair S gc/Reply)) state: S spent: Int64 -> (Pair S Outcome)
  (let [(half (halfFor tr.task (armLang tr.arm)))
        (t0 (monotonicNs))]
    (match (makeSandbox! cfg (armLang tr.arm) (trialKey tr) half)
      ((err e)
        (pair state (Outcome :trial tr :acc (accStop (emptyAcc spent) "sandbox" e)
                             :verdict (Verdict :suiteOk false :acceptOk false :absentOk false :solved false :detail e) :wallMs 0)))
      ((ok sb)
        (let [(res (turnLoop! cfg tr sb (systemFor cfg tr.arm) (list (pair "user" (userFor sb half))) 1 call state (emptyAcc spent)))
              (v (grade! cfg sb half))]
          (pair (pairFirst res) (Outcome :trial tr :acc (pairSecond res) :verdict v :wallMs (/ (- (monotonicNs) t0) 1000000)))))))

fn intList xs: (List Int64) -> String
  (str "(" (stringJoin (map stringFromInt64 xs) " ") ")")

fn boolText b: Bool -> String
  (if b "true" "false")

fn trialRow o: Outcome cost: Int64 -> String
  (str "(:trial :key " (gc/asnQuote (trialKey o.trial)) " :arm " (gc/asnQuote o.trial.arm) " :task " (gc/asnQuote o.trial.task.id)
       " :kind " (gc/asnQuote o.trial.task.kind) " :model " (gc/asnQuote o.trial.model) " :served " (gc/asnQuote o.acc.served)
       " :rep " (stringFromInt64 o.trial.rep) " :solved " (boolText o.verdict.solved) " :stop " (gc/asnQuote o.acc.stop)
       " :suiteOk " (boolText o.verdict.suiteOk) " :acceptOk " (boolText o.verdict.acceptOk) " :absentOk " (boolText o.verdict.absentOk)
       " :turns " (stringFromInt64 o.acc.turns) " :tokIn " (intList o.acc.tokIn) " :tokOut " (intList o.acc.tokOut)
       " :tokInSum " (stringFromInt64 (listSum o.acc.tokIn)) " :tokOutSum " (stringFromInt64 (listSum o.acc.tokOut))
       " :filesRead " (stringFromInt64 (listLength o.acc.files)) " :bytesRead " (stringFromInt64 o.acc.bytesRead)
       " :calls (" (stringJoin (map gc/asnQuote o.acc.calls) " ") ")"
       " :costPico " (stringFromInt64 cost) " :wallMs " (stringFromInt64 o.wallMs)
       " :error " (gc/asnQuote (gc/clip o.acc.error 300)) " :detail " (gc/asnQuote (if o.verdict.solved "" o.verdict.detail)) ")")

fn skipped rs: RunState -> RunState
  (with rs :skipped (+ rs.skipped 1))

fn ranOne rs: RunState spent: Int64 stopped: String -> RunState
  (with rs :spent spent :done (+ rs.done 1) :stopped stopped)

fn stoppedOf rs: RunState -> String
  rs.stopped

fn spentOf rs: RunState -> Int64
  rs.spent

fn ! trialStep! cfg: Cfg existing: String call: (fn [S gc/Req] -> (Pair S gc/Reply)) acc: (Pair S RunState) tr: Trial -> (Pair S RunState)
  (let [(rs (pairSecond acc))
        (spentBefore (spentOf rs))]
    (cond
      ((not (stringEmpty? (stoppedOf rs))) acc)
      ((stringContains? existing (str ":key " (gc/asnQuote (trialKey tr)) " ")) (pair (pairFirst acc) (skipped rs)))
      (else
        (let [(res (loopTrial! cfg tr call (pairFirst acc) spentBefore))
              (o (pairSecond res))
              (wrote (fileAppend cfg.out (str (trialRow o (- o.acc.spent spentBefore)) "\n")))
              (said (println (str "(:trialDone :key " (gc/asnQuote (trialKey tr)) " :solved " (boolText o.verdict.solved) " :stop " (gc/asnQuote o.acc.stop)
                                  " :turns " (stringFromInt64 o.acc.turns) " :tokens " (stringFromInt64 (+ (listSum o.acc.tokIn) (listSum o.acc.tokOut)))
                                  " :spentUsd " (gc/asnQuote (gc/usdText o.acc.spent)) ")")))]
          (pair (pairFirst res)
                (ranOne rs o.acc.spent
                        (cond
                          ((err? wrote) "the results file cannot be written")
                          ((= o.acc.stop "budget") "the spend cap would be exceeded by the next call")
                          (else ""))))))))

fn ! runAll! cfg: Cfg trials: (List Trial) existing: String spentBefore: Int64 call: (fn [S gc/Req] -> (Pair S gc/Reply)) state: S -> (Pair S RunState)
  (fold (fn [acc tr] (trialStep! cfg existing call acc tr))
        (pair state (RunState :spent spentBefore :done 0 :skipped 0 :stopped ""))
        trials)

fn ! verifyTask! cfg: Cfg t: LoopTask lang: String -> (Pair Bool String)
  (let [(half (halfFor t lang))]
    (if (stringEmpty? half.prompt)
      (pair false "no task half for this language")
      (match (makeSandbox! cfg lang (str "verify-" lang "-" t.id) half)
        ((err e) (pair false e))
        ((ok sb)
          (let [(before (grade! cfg sb half))
                (applied (applyEdits! sb.pkg half.refs))
                (after (if (ok? applied) (grade! cfg sb half) (Verdict :suiteOk false :acceptOk false :absentOk false :solved false :detail "ref")))]
            (cond
              ((err? applied) (pair false (str "reference edit: " (match applied ((err e) e) ((ok _) "")))))
              (before.solved (pair false "the seeded state already passes: the task has no red"))
              ((not after.solved) (pair false (str "the reference solution is not green: " after.detail)))
              (else (pair true "red before, green after the reference edits"))))))))

fn scriptCaller scripts: (List (Pair String (List String))) -> (fn [Int64 gc/Req] -> (Pair Int64 gc/Reply))
  (fn [(n Int64) (r gc/Req)] -> (Pair Int64 gc/Reply)
    (let [(script (match (listFind (fn [(p (Pair String (List String)))] -> Bool (= (pairFirst p) (str r.arm "|" r.task))) scripts)
                    ((some p) (pairSecond p))
                    ((none) (list))))
          (text (optionOr (listGet script (- r.turn 1)) "<tool>done</tool>"))]
      (pair (+ n 1) (gc/Reply :text text :tokIn (+ 1 (/ (gc/reqChars r) 4)) :tokOut (+ 1 (/ (stringLength text) 4)) :served "fake" :error ""))))

fn ! pristineSha! root: String lang: String -> String
  (let [(dir (pristineOf root lang))]
    (gc/sha256Of (stringJoin (listFlatMap (fn [(d String)] -> (List String)
                                            (map (fn [(n String)] -> String (resultOr (fileReadString (str dir "/" d "/" n)) "")) (namesIn (str dir "/" d) (extOf lang))))
                                          (list (srcDirOf lang) "tests"))
                             "\n")))

fn ! headerRow root: String mode: String models: (List String) arms: (List String) tasks: (List LoopTask) reps: Int64 cfg: Cfg date: String note: String -> String
  (str "(:run :id \"LOOPBENCH\" :protocol \"asl/doc/loopBenchmark.md v1\" :mode " (gc/asnQuote mode)
       " :models (" (stringJoin (map gc/asnQuote models) " ") ")"
       " :arms (" (stringJoin (map gc/asnQuote arms) " ") ")"
       " :taskIds (" (stringJoin (map (fn [(t LoopTask)] -> String (gc/asnQuote t.id)) tasks) " ") ")"
       " :reps " (stringFromInt64 reps) " :maxTurns " (stringFromInt64 cfg.maxTurns) " :maxTokens " (stringFromInt64 cfg.maxTokens)
       " :trialTokens " (stringFromInt64 cfg.trialTokens) " :resultClip " (stringFromInt64 cfg.resultClip) " :temperature \"0.2\""
       " :priceInMicroPerM " (stringFromInt64 cfg.priceIn) " :priceOutMicroPerM " (stringFromInt64 cfg.priceOut)
       " :capUsd " (gc/asnQuote (gc/usdText cfg.capPico))
       " :pristineSha256 ((:lang \"asl\" :sha " (gc/asnQuote (pristineSha! root "asl")) ") (:lang \"py\" :sha " (gc/asnQuote (pristineSha! root "py")) "))"
       " :date " (gc/asnQuote date) " :note " (gc/asnQuote note) ")")

fn ! removeWork! dir: String -> Bool
  (if (or (stringEmpty? dir) (= dir "/") (not (stringContains? dir "aslLoopBench")))
    false
    (= (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "/" (fr/childEnv (list))) (fr/limits 60 4)).exit 0))
