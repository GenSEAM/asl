(module asl-store/tests/purityTest
  :x [runTests]
  :i [(asl-store/purity :a pu)])

; (:m :ref VS-CORE :do "asl-store, asl-vault and asl-context are pure: no source file calls the clock, environment, file, process or socket builtins; a package not yet created is skipped, and VS-COORD adds asl-coord (except locate) when it makes that package pure")
fn pureDirs -> (List String)
  (list "asl/packages/asl-store/src" "asl/packages/asl-vault/src" "asl/packages/asl-context/src")

fn exempt? path: String -> Bool
  (stringEndsWith? path "asl-coord/src/locate.asl")

fn ! filesOf! dir: String -> (List String)
  (match (dirList dir)
    ((ok names) (map (fn [(n String)] -> String (str dir "/" n)) (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asl")) names)))
    ((err _) (list)))

fn ! hitsOf! path: String -> (List String)
  (match (fileReadString path)
    ((ok text) (map (fn [(h String)] -> String (str path " " h)) (pu/impureHits text)))
    ((err e) (list (str path " unreadable " e))))

fn ! realHits! -> (List String)
  (fold (fn [(a (List String)) (p String)] -> (List String) (listAppend a (hitsOf! p)))
        (list)
        (filter (fn [(p String)] -> Bool (not (exempt? p))) (fold (fn [(a (List String)) (d String)] -> (List String) (listAppend a (filesOf! d))) (list) (pureDirs))))

fn ! runTests -> Bool
  (let [(planted "(module m :x [f] :i [])\nfn ! f -> String\n  (fileReadString \"/etc/hosts\")")
        (quoted "(module m :x [f] :i [])\n; (:m :do \"calls (fileReadString) never\")\nfn f -> String\n  \"(nowNs) is a word here\"")
        (real (realHits!))]
    (do (assert (= (pu/impureHits planted) (list "(fileRead")) "a planted fileRead in a pure module is reported")
        (assert (listEmpty? (pu/impureHits quoted)) "banned names inside strings and comments are not calls")
        (assert (listEmpty? real) (str "pure vault packages call host builtins: " (stringJoin real "; ")))
        (assert (> (listLength (filesOf! "asl/packages/asl-store/src")) 5) "the scan really sees the asl-store sources")
        true))
