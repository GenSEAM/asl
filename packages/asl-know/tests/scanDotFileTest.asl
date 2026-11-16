(module asl-know/scanDotFileTest
  :x [runTests]
  :i [(asl-know/scan :a sc)])

; (:m :ref TRAIN-DERIVED-REGEN :do "a leaked check temp (.asl_chk_print_pPID_NS_0.asl) or any dot dir beside a package source is not a source: sourceFiles! lists the plain source only, so the cards of a polluted tree equal those of a clean one")

fn names files: (List String) dir: String -> (List String)
  (map (fn [(f String)] -> String (if (stringStartsWith? f (str dir "/")) (optionOr (stringSlice f (+ (stringLength dir) 1) (stringLength f)) f) f)) files)

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/scanDotFile-" (procSelf) "-" (/ (monotonicNs) 1000)))
        (src (str dir "/src"))
        (made (and (ok? (dirCreate src)) (ok? (dirCreate (str src "/.hidden")))))
        (wrote (and (ok? (fileWrite (str src "/a.asl") "(module p/a\n  :x [f]\n  :i [])\nfn f -> Bool\n  true\n"))
                    (and (ok? (fileWrite (str src "/.asl_chk_print_p1_2_0.asl") "(module p/a\n  :x [f leak]\n  :i [])\nfn leak -> Bool\n  true\n"))
                         (ok? (fileWrite (str src "/.hidden/b.asl") "(module p/b\n  :x [g]\n  :i [])\nfn g -> Bool\n  true\n")))))
        (files (names (sc/sourceFiles! src) src))
        (_ (pathRemove dir))]
    (do
      (assert (and made wrote) "fixture tree written")
      (assert (listContains? files "a.asl") "the plain source is listed")
      (assert (not (listContains? files ".asl_chk_print_p1_2_0.asl")) "a leaked check temp beside a source is not listed")
      (assert (not (listContains? files ".hidden/b.asl")) "a source under a dot dir is not listed")
      (assert (= (listLength files) 1) "exactly the one plain source is listed")
      true))
