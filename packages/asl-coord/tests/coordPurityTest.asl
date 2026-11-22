(module asl-coord/tests/coordPurityTest
  :x [runTests]
  :i [(asl-store/purity :a pu)])

; (:m :ref VS-COORD :do "asl-coord is pure except asl-coord/locate: no other source file calls the clock, environment, file, process or socket builtins, so the rules receive them as a Ctx; the same scan asl-store's purityTest uses")
fn ! hitsOf! path: String -> (List String)
  (match (fileReadString path)
    ((ok text) (map (fn [(h String)] -> String (str path " " h)) (pu/impureHits text)))
    ((err e) (list (str path " unreadable " e))))

fn ! sources! -> (List String)
  (let [(dir "asl/packages/asl-coord/src")]
    (match (dirList dir)
      ((ok names) (map (fn [(n String)] -> String (str dir "/" n)) (filter (fn [(n String)] -> Bool (and (stringEndsWith? n ".asl") (!= n "locate.asl"))) names)))
      ((err _) (list))))

fn ! runTests -> Bool
  (let [(files (sources!))
        (hits (fold (fn [(a (List String)) (p String)] -> (List String) (listAppend a (hitsOf! p))) (list) files))]
    (do (assert (>= (listLength files) 6) "the scan sees the pure asl-coord sources")
        (assert (listEmpty? hits) (str "pure asl-coord modules call host builtins: " (stringJoin hits "; ")))
        true))
