(module asl-target-llvm/tests/mapReuseTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/tests/rcTest :a rc)])

fn fixture name: String -> String
  (str "asl/packages/asl-target-llvm/tests/fixtures/mapReuse/" name ".asl")

; (:m :ref MAPREUSE :do "oracle from the tracing build, which keeps the copying treap: a snapshot kept across inserts and bumps, a map held in a list, a map captured by a closure, then changed through later sets and removes, each keeps its own contents; String keys replaced and removed; a unique map filled, bumped and emptied")
fn want -> String
  "snap 3000:3000:4498500:539422320\nm2 4000:4000:1507998000:498369380\nheld 4000:4000:1507998000:498369380\nm3 3300:3300:1807753350:157592716\nseen 3300:3300:1807753350:157592716\nm4 4000:4000:7998000:498369380 true\ns1 211 21119 22500 true\ns2 210 -1 0 false\nu 0:0:0:0\n"

fn wantUnique -> String
  "5000 5037497500\n"

fn marker -> String
  "; treapRt in place"

fn refInsert -> String
  "define tailcc %Val @prelude$2EpreludeTreeInsert$ref("

fn ! build! libs: rc/Libs dir: String name: String mode: String -> (Result (Pair String rc/Captured) String)
  (match (lk/linkEntry! (fixture name))
    ((err ds) (err (str name " links: " (rc/diagText ds))))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
              ((err ds) (err (str name " emits in mode " mode ": " (rc/diagText ds))))
              ((ok code)
                (let [(ll (str dir "/" name "." mode ".ll")) (exe (str dir "/" name "." mode))]
                  (match (fileWrite ll code)
                    ((err e) (err (str "cannot write " ll ": " e)))
                    ((ok _) (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
                              (if (!= linked.exitCode 0)
                                (err (str name " " mode " links: " linked.stderr))
                                (ok (pair code (rc/sh (rc/shellQuote exe)))))))))))))

fn ! testMode libs: rc/Libs dir: String mode: String inPlace: Bool -> Bool
  (match (build! libs dir "mapReuse" mode)
    ((err e) (do (assert false e) false))
    ((ok built)
      (let [(code (pairFirst built)) (run (pairSecond built))]
        (do (assert (= run.exitCode 0) (str mode " exits 0: " run.stderr))
            (assert (= run.stdout (want)) (str mode " prints what the persistent Map gives: every shared version keeps its contents: " run.stdout))
            (refute (stringContains? run.stderr "Sanitizer") (str mode " reads no released node and changes no shared one: " run.stderr))
            (if inPlace
              (do (assert (stringContains? code (marker)) (str mode " gives the treap writes their in-place front"))
                  (assert (stringContains? code (refInsert)) (str mode " keeps the copying insert as the reference for shared nodes")))
              (do (refute (stringContains? code (marker)) (str mode " keeps the copying treap writes"))
                  (refute (stringContains? code (refInsert)) (str mode " has no reference split"))))
            true))))

; (:m :ref MAPREUSE :do "a unique map's 25000 writes (10000 inserts, 10000 replaces, 5000 removes) run in place: the only resets left are the one per write of the map record itself (25000), where the copying path resets every node on the path as well (base fc9f98caf: resets 441834, fbip 367628)")
fn ! testUnique libs: rc/Libs dir: String -> Bool
  (match (build! libs dir "mapUnique" "asanNotrace")
    ((err e) (do (assert false e) false))
    ((ok built)
      (let [(run (pairSecond built)) (resets (rc/statOf run.stderr "resets")) (fbip (rc/statOf run.stderr "fbip"))]
        (do (assert (= run.stdout (wantUnique)) (str "asanNotrace prints the oracle for the unique map: " run.stdout))
            (refute (stringContains? run.stderr "Sanitizer") (str "the in-place writes read no released node: " run.stderr))
            (assert (and (>= resets 25000) (<= resets 26000)) (str "a unique map is written in place, one reset per write for its record: resets " resets ", base 441834, in " run.stderr))
            (assert (and (>= fbip 0) (<= fbip 26000)) (str "no tree node is reset and reused for a copy: fbip " fbip ", base 367628, in " run.stderr))
            true))))

; (:m :ref MAPREUSE :do "a fixture whose untraced builds must print what its tracing build prints, the copying reference: mapAlias keeps versions of a map in a list, a schema field, a closure, a HashMap value, a pair and a map of maps while later versions change, and runs the in-place fronts; mapArena fills a map outside an arenaRun and inside it, so its fronts stay off (an in-place write there would link a heap node to an arena cell)")
fn ! testSame libs: rc/Libs dir: String name: String head: String inPlace: Bool -> Bool
  (match (build! libs dir name "0")
    ((err e) (do (assert false e) false))
    ((ok traced)
      (let [(oracle (pairSecond traced).stdout)]
        (do (assert (= (pairSecond traced).exitCode 0) (str name " tracing exits 0: " (pairSecond traced).stderr))
            (assert (stringStartsWith? oracle head) (str name " tracing prints its rows: " oracle))
            (fold (fn [(acc Bool) (mode String)] -> Bool
                    (match (build! libs dir name mode)
                      ((err e) (do (assert false e) false))
                      ((ok built)
                        (let [(code (pairFirst built)) (run (pairSecond built))]
                          (do (assert (= run.exitCode 0) (str name " " mode " exits 0: " run.stderr))
                              (assert (= run.stdout oracle) (str name " " mode " prints what tracing prints: " run.stdout " want " oracle))
                              (refute (stringContains? run.stderr "Sanitizer") (str name " " mode " reads no released node: " run.stderr))
                              (if inPlace
                                (assert (stringContains? code (marker)) (str name " " mode " runs the in-place fronts"))
                                (refute (stringContains? code (marker)) (str name " " mode " opens an arena, so it keeps the copying treap writes")))
                              acc)))))
                  true (list "notrace" "asanNotrace"))))))

fn ! clean dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))]
    (do (fold (fn [(acc Bool) (n String)] -> Bool (and (ok? (pathRemove (str dir "/" n))) acc)) true names)
        (ok? (pathRemove dir))))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/mapReuseTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "work directory created")
        (match (rc/runtimes!)
          ((err e) (assert false (str "runtimes: " e)))
          ((ok libs) (do (assert (testMode libs dir "0" false) "tracing build")
                         (assert (testMode libs dir "notrace" true) "untraced RC build")
                         (assert (testMode libs dir "asanNotrace" true) "untraced RC build under ASan")
                         (assert (testUnique libs dir) "untraced RC writes a unique map in place")
                         (assert (testSame libs dir "mapAlias" "m0 " true) "aliased versions keep their contents under untraced RC")
                         (assert (testSame libs dir "mapArena" "r " false) "a module with an arena keeps the copying treap writes"))))
        (assert (clean dir) "work directory removed")
        true))
