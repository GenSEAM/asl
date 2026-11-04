(module asl-tools/coord/brief
  :x [moduleOfPath ownedFact sizeAdviceFree briefFor]
  :i [])

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
