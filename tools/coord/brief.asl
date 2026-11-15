(module asl-tools/coord/brief
  :x [moduleOfPath ownedFact sizeAdviceFree briefFor outlineLines outlineRows outlineFor outlineFor! namedPaths]
  :i [(asl-forms/symbol :a sy)])

; (:m :ref COND-TASK-SPEC :do "the facts a writer needs about its owned paths, added to the task text at claim and never written back to the store: each path is exists (N lines) or missing with the instruction to create it with one write, and the module name derived from the path, so no turn is spent reading a file that does not exist yet or guessing asl-text for a unit in asl-utils")
fn stripAsl path: String -> String
  (if (stringEndsWith? path ".asl") (optionOr (stringSlice path 0 (- (stringLength path) 4)) path) path)

fn dropPrefix s: String prefix: String -> String
  (if (stringStartsWith? s prefix) (optionOr (stringSlice s (stringLength prefix) (stringLength s)) s) s)

; (:m :ref COND-TASK-SPEC :do "module name of a source path: asl/packages/P/src/X.asl is P/X, asl/tools/A/B.asl is asl-tools/A/B, any other path is itself without .asl; empty for a path that is not an .asl file")
fn moduleOfPath path: String -> String
  (cond
    ((not (stringEndsWith? path ".asl")) "")
    ((stringStartsWith? path "asl/packages/")
      (let [(rest (dropPrefix path "asl/packages/"))
            (parts (stringSplit rest "/"))
            (pkg (optionOr (listHead parts) ""))
            (after (stringJoin (listDrop parts 1) "/"))]
        (str pkg "/" (stripAsl (dropPrefix after "src/")))))
    ((stringStartsWith? path "asl/tools/") (str "asl-tools/" (stripAsl (dropPrefix path "asl/tools/"))))
    (else (stripAsl path)))

; (:m :ref COND-TASK-SPEC :do "one owned path: lines is -1 when the file does not exist at claim")
fn ownedFact path: String lines: Int64 -> String
  (let [(mod (moduleOfPath path))
        (modNote (if (stringEmpty? mod) "" (str "; module " mod)))]
    (if (< lines 0)
      (str "- " path ": missing, create it with one write" modNote)
      (str "- " path ": exists (" (stringFromInt64 lines) " lines)" modNote)))

; (:m :ref COND-TASK-SPEC :do "size advice (SMALL EDITS ONLY...) is about editing a file that exists; when an owned file is missing the lines carrying it are dropped from the brief")
fn sizeAdviceFree task: String -> String
  (stringJoin (filter (fn [(l String)] -> Bool (not (stringContains? (stringLower l) "small edits only"))) (stringLines task)) "\n")

; (:m :ref COND-TASK-SPEC :do "the brief is the stored task text, size advice dropped when an owned file is missing, then an owned-paths block with each path's state at claim and its module name, and a line saying the owned paths are authoritative over any module name the text names; no owned paths leaves the text as it is")
fn briefFor task: String owned: (List (Pair String Int64)) -> String
  (if (listEmpty? owned) task
    (let [(anyMissing (listAny? (fn [(p (Pair String Int64))] -> Bool (< (pairSecond p) 0)) owned))
          (text (if anyMissing (sizeAdviceFree task) task))
          (facts (stringJoin (map (fn [(p (Pair String Int64))] -> String (ownedFact (pairFirst p) (pairSecond p))) owned) "\n"))]
      (str text "\n\nOwned paths at claim (paths are authoritative; a module name in the text above is not a path):\n" facts)))

; (:m :ref BRIEF-OUTLINE-ANCHORS :do "files longer than this many lines get an outline in the brief; at most outlineFileCap rows per file and outlineBriefCap rows per brief")
fn outlineMinLines -> Int64 300
fn outlineFileCap -> Int64 80
fn outlineBriefCap -> Int64 200

fn isUpperChar c: String -> Bool
  (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" c)

fn isAlnumChar c: String -> Bool
  (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" c)

; (:m :ref BRIEF-OUTLINE-ANCHORS :do "lowercase words of a name or text: camelCase boundaries and any non alphanumeric character split, words under 3 characters dropped, so ownedFact is owned and fact and a task naming a fact matches it")
fn nameWords s: String -> (List String)
  (let [(st (fold (fn [(acc (Pair (List String) String)) (c String)] -> (Pair (List String) String)
                    (cond
                      ((not (isAlnumChar c)) (pair (cons (pairSecond acc) (pairFirst acc)) ""))
                      ((isUpperChar c) (pair (cons (pairSecond acc) (pairFirst acc)) (stringLower c)))
                      (else (pair (pairFirst acc) (str (pairSecond acc) (stringLower c))))))
                  (pair (list) "") (stringChars s)))
        (all (cons (pairSecond st) (pairFirst st)))]
    (filter (fn [(w String)] -> Bool (>= (stringLength w) 3)) (listReverse all)))

fn namedInTask? words: (List String) name: String -> Bool
  (listAny? (fn [(w String)] -> Bool (listContains? words w)) (nameWords name))

; (:m :ref BRIEF-OUTLINE-ANCHORS :do "top level definitions of an asl or asn text as (name, first line, last line) in file order; other languages give none")
fn outlineLines path: String text: String -> (List (Pair String (Pair Int64 Int64)))
  (if (not (or (stringEndsWith? path ".asl") (stringEndsWith? path ".asn"))) (list)
    (map (fn [(d sy/SymbolDef)] -> (Pair String (Pair Int64 Int64))
           (pair d.name (pair (sy/lineOf text d.start) (sy/lineOf text (max d.start (- d.end 1))))))
         (filter (fn [(d sy/SymbolDef)] -> Bool (= d.depth 0)) (sy/aslSymbols text))))

fn defRow d: (Pair String (Pair Int64 Int64)) -> String
  (str "(:d " (pairFirst d) " :from " (stringFromInt64 (pairFirst (pairSecond d))) " :to " (stringFromInt64 (pairSecond (pairSecond d))) ")")

; (:m :ref BRIEF-OUTLINE-ANCHORS :do "the definitions kept under a cap: all in file order when they fit, else those sharing a word with the task first, then the rest in file order")
fn outlineKeep defs: (List (Pair String (Pair Int64 Int64))) words: (List String) cap: Int64 -> (List (Pair String (Pair Int64 Int64)))
  (if (<= (listLength defs) cap) defs
    (listTake (listAppend (filter (fn [(d (Pair String (Pair Int64 Int64)))] -> Bool (namedInTask? words (pairFirst d))) defs)
                          (filter (fn [(d (Pair String (Pair Int64 Int64)))] -> Bool (not (namedInTask? words (pairFirst d)))) defs))
              cap))

; (:m :ref BRIEF-OUTLINE-ANCHORS :do "the outline rows of one file within a row budget: (:outline :file P :lines N :defs ((:d name :from A :to B) ... (:left K))), the :left row only when definitions were cut; empty for a file of outlineMinLines or fewer or without definitions")
fn outlineRows path: String text: String task: String budget: Int64 -> String
  (let [(n (listLength (stringLines text)))
        (defs (outlineLines path text))]
    (if (or (<= n (outlineMinLines)) (listEmpty? defs) (< budget 0)) ""
      (let [(keep (outlineKeep defs (nameWords task) (min (outlineFileCap) budget)))
            (left (- (listLength defs) (listLength keep)))
            (rows (map defRow keep))
            (all (if (> left 0) (listAppend rows (list (str "(:left " (stringFromInt64 left) ")"))) rows))]
        (str "(:outline :file \"" path "\" :lines " (stringFromInt64 n) " :defs (" (stringJoin all " ") "))"))))

fn rowCount block: String -> Int64
  (- (listLength (stringSplit block "(:d ")) 1)

fn delimChar? c: String -> Bool
  (stringContains? "\"'`()[]{}<>,; \t\r\n" c)

fn trimTail s: String -> String
  (if (and (> (stringLength s) 0) (or (stringEndsWith? s ".") (stringEndsWith? s ":")))
    (trimTail (optionOr (stringSlice s 0 (- (stringLength s) 1)) s)) s)

fn pathLike? p: String -> Bool
  (and (stringContains? p "/") (not (stringStartsWith? p "/")) (not (stringContains? p ".."))
       (listAny? (fn [(e String)] -> Bool (stringEndsWith? p e)) (list ".asl" ".asn")))

; (:m :ref BRIEF-OUTLINE-ANCHORS :do "relative asl and asn paths a task text names, in first-seen order without repeats")
fn namedPaths task: String -> (List String)
  (let [(toks (stringSplit (stringJoin (map (fn [(c String)] -> String (if (delimChar? c) " " c)) (stringChars task)) "") " "))]
    (listReverse (fold (fn [(acc (List String)) (t String)] -> (List String)
                         (let [(p (trimTail t))] (if (and (pathLike? p) (not (listContains? acc p))) (cons p acc) acc)))
                       (list) toks)))

; (:m :ref BRIEF-OUTLINE-ANCHORS :do "pure outline block over (path, text) sources, owned first then named: one outline per file over the threshold within outlineBriefCap rows, then one instruction row; empty when no file qualifies")
fn outlineFor task: String sources: (List (Pair String String)) -> String
  (let [(res (fold (fn [(acc (Pair (List String) Int64)) (s (Pair String String))] -> (Pair (List String) Int64)
                     (let [(blk (outlineRows (pairFirst s) (pairSecond s) task (- (outlineBriefCap) (pairSecond acc))))]
                       (if (stringEmpty? blk) acc (pair (cons blk (pairFirst acc)) (+ (pairSecond acc) (rowCount blk))))))
                   (pair (list) 0) sources))
        (blocks (listReverse (pairFirst res)))]
    (if (listEmpty? blocks) ""
      (str "\n\n" (stringJoin blocks "\n") "\n(:instruction :do \"read these files by symbol (:read :file F :symbol S) or by slice from the ranges above, never by paging from line 1\")")))
fn ! sourceOf! wt: String p: String -> (List (Pair String String))
  (match (fileReadString (str wt "/" p))
    ((ok t) (list (pair p t)))
    ((err _) (list)))

; (:m :ref BRIEF-OUTLINE-ANCHORS :do "outline block for a write brief: owned files that exist, then files the task text names that are not owned, read from the unit worktree, directories and missing files skipped")
fn ! outlineFor! wt: String owns: (List String) task: String -> String
  (let [(paths (listAppend (filter (fn [(p String)] -> Bool (not (stringEndsWith? p "/"))) owns)
                           (filter (fn [(p String)] -> Bool (not (listContains? owns p))) (namedPaths task))))]
    (outlineFor task (listFlatMap (fn [(p String)] -> (List (Pair String String)) (sourceOf! wt p)) paths)))
