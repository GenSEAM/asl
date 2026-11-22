(module asl-vault/tests/purityTest
  :x [runTests]
  :i [(asl-store/purity :a pu)])

fn ! filesOf! -> (List String)
  (match (dirList "asl/packages/asl-vault/src")
    ((ok names) (map (fn [(n String)] -> String (str "asl/packages/asl-vault/src/" n)) (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asl")) names)))
    ((err _) (list)))

fn ! hitsOf! path: String -> (List String)
  (match (fileReadString path)
    ((ok text) (map (fn [(h String)] -> String (str path " " h)) (pu/impureHits text)))
    ((err e) (list (str path " unreadable " e))))

; (:m :ref VS-VAULT :do "asl-vault is pure: none of its source files calls a clock, environment, file, process or socket builtin, and the scan provably sees every module of the manifest")
fn ! runTests -> Bool
  (let [(files (filesOf!))
        (hits (fold (fn [(a (List String)) (p String)] -> (List String) (listAppend a (hitsOf! p))) (list) files))]
    (do
      (assert (= (listLength files) 7) "the scan sees time, codec, unit, model, graph, curate and vault")
      (assert (listEmpty? hits) (str "asl-vault calls host builtins: " (stringJoin hits "; ")))
      (assert (= (pu/impureHits "(module m :x [f] :i [])\nfn ! f -> Int64\n  (nowNs)") (list "(nowNs")) "a planted clock read in a pure module is reported")
      true))
