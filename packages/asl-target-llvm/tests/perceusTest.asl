(module asl-target-llvm/tests/perceusTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/tests/rcTest :a rc)])

fn fixture -> String
  "asl/packages/asl-target-llvm/tests/fixtures/perceus/perceus.asl"

; (:m :ref PERCEUS :do "oracle from the tracing build, which reuses nothing: a kept tree next to its grown copy, grown shapes, a value kept in a pair, a resized shape, an incremented list, a raw record and a boxed record updated in loops next to a kept one, Option and Result rebuilt in loops")
fn want -> String
  "17728 18176 1817600\n25689600 200\n5 6 42\n2003000 2000\nacc 3000 4498500\n41 a,b s sx\n3001 9002 e!!!\n"

fn ! build! libs: rc/Libs dir: String mode: String patch: (fn [String] -> String) label: String -> (Result (Pair String rc/Captured) String)
  (match (lk/linkEntry! (fixture))
    ((err ds) (err (str "fixture links: " (rc/diagText ds))))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
              ((err ds) (err (str "fixture emits in mode " mode ": " (rc/diagText ds))))
              ((ok code0)
                (let [(code (patch code0)) (ll (str dir "/perceus." label ".ll")) (exe (str dir "/perceus." label))]
                  (match (fileWrite ll code)
                    ((err e) (err (str "cannot write " ll ": " e)))
                    ((ok _) (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
                              (if (!= linked.exitCode 0)
                                (err (str "fixture " mode " links: " linked.stderr))
                                (ok (pair code (rc/sh (str "ASL_RC_STATS=1 " (rc/shellQuote exe))))))))))))))

fn same code: String -> String
  code

; (:m :ref PERCEUS :do "the reuse-off build: every reset recycles its unique cell instead of handing it over, so each construct allocates fresh; what it holds at exit is the reference for the reuse build")
fn noGive code: String -> String
  (stringReplace (stringReplace code "  br i1 %fits, label %give, label %spare" "  br label %spare") "  br i1 %fitsHere, label %give, label %spare" "  br label %spare")

; (:m :ref PERCEUS :do "cells the fixture holds at exit under notraceStats (globals, interned strings), measured on 981780430; a reset that stops releasing a unique cell's kids leaks thousands (audit mutant: 3061) in the reuse build and the reuse-off build alike, so held is pinned, not only compared")
fn heldAtExit -> Int64
  21

fn body code: String name: String -> String
  (match (stringIndexOf code (str "define tailcc %Val @perceus$2E" name "("))
    ((none) "")
    ((some at) (let [(rest (optionOr (stringSlice code at (stringLength code)) ""))]
                 (match (stringIndexOf rest "\n}\n") ((some e) (optionOr (stringSlice rest 0 e) "")) ((none) rest)))))

fn reuses? code: String name: String -> Bool
  (let [(b (body code name))] (and (stringContains? b "@aslRcReset_") (stringContains? b "@aslRc.reuseOr")))

; (:m :ref PERCEUS :do "on a give path the cell is rewritten in place, not freed, so ASan sees no use after free there; the oracle for a wrongly handed-over shared cell is stdout equal to the tracing build (kept tree, kept tag), ASan only covers the freed paths")
fn ! testMode libs: rc/Libs dir: String mode: String -> Bool
  (match (build! libs dir mode same mode)
    ((err e) (do (assert false e) false))
    ((ok built)
      (let [(run (pairSecond built))]
        (do (assert (= run.exitCode 0) (str mode " exits 0: " run.stderr))
            (assert (= run.stdout (want)) (str mode " prints what the tracing build prints: every kept value keeps its contents: " run.stdout))
            (refute (stringContains? run.stderr "Sanitizer") (str mode " reads no released cell and changes no shared one: " run.stderr))
            true))))

fn ! testIr libs: rc/Libs dir: String -> Bool
  (match (build! libs dir "notrace" same "ir")
    ((err e) (do (assert false e) false))
    ((ok built)
      (let [(code (pairFirst built))]
        (do (assert (reuses? code "grow") (str "a map over a variant resets the matched cell into the rebuilt one: " (body code "grow")))
            (assert (reuses? code "addItem") (str "a record update of a raw record reuses the old record: " (body code "addItem")))
            (assert (reuses? code "relabel") (str "a record update of a boxed record reuses the old record: " (body code "relabel")))
            (assert (reuses? code "bump") (str "an Option rebuild reuses the some cell: " (body code "bump")))
            (assert (reuses? code "fix") (str "a Result rebuild reuses the ok and err cells: " (body code "fix")))
            (assert (reuses? code "incAll") (str "a list map reuses each cons: " (body code "incAll")))
            (assert (stringContains? (body code "fix") "@aslRcReset_2_0") (str "a Result cell resets for the class of its rebuilt cell: " (body code "fix")))
            (refute (stringContains? (body code "area") "@aslRcReset_") (str "a rect (class 4) never resets into a circle (class 2): sizes differ: " (body code "area")))
            (refute (stringContains? (body code "both") "@aslRcReset_") (str "a matched value that escapes into the result is not dead, so nothing is reset: " (body code "both")))
            (assert (stringContains? (body code "area") "@aslRc.allocFast.2(") "the resized shape allocates a fresh circle")
            true))))

; (:m :ref PERCEUS :do "under ASan every reset that hands its cell over counts as fbip; a unique cell is handed over once per rebuild (fill 3000, bumpN 3000, fixN 3003, incAll 4000, growAll 400, grows of fresh trees and shapes), while the kept tree and the kept tag are shared at their reset; held cells at exit (fresh + reused - freed) equal the reuse-off build's")
fn ! testCounts libs: rc/Libs dir: String -> Bool
  (match (build! libs dir "asanNotrace" same "asan")
    ((err e) (do (assert false e) false))
    ((ok a) (match (build! libs dir "notraceStats" same "stats")
      ((err e) (do (assert false e) false))
      ((ok s) (match (build! libs dir "notraceStats" noGive "off")
        ((err e) (do (assert false e) false))
        ((ok o) (let [(sa (pairSecond a).stderr) (ss (pairSecond s).stderr) (so (pairSecond o).stderr)
                      (fbip (rc/statOf sa "fbip"))
                      (held (fn [(t String)] -> Int64 (- (+ (rc/statOf t "fresh") (rc/statOf t "reused")) (rc/statOf t "freed"))))]
                  (do (assert (= (pairSecond a).stdout (want)) (str "asanNotrace prints the oracle: " (pairSecond a).stdout))
                      (assert (= (pairSecond o).stdout (want)) (str "the reuse-off build prints the oracle: " (pairSecond o).stdout))
                      (assert (>= fbip 19000) (str "unique cells are handed over to their rebuilds: fbip " fbip " in " sa))
                      (assert (= (rc/statOf so "fbip") 0) (str "the reuse-off build hands no cell over: " so))
                      (assert (> (rc/statOf ss "fbip") 19000) (str "notraceStats counts the same handovers: " ss))
                      (assert (< (rc/statOf ss "freed") (rc/statOf so "freed")) (str "a handed-over cell is not freed: " ss " vs " so))
                      (assert (and (>= (held ss) 0) (= (held ss) (held so))) (str "reuse leaks nothing: held at exit " (held ss) " equals the reuse-off build's " (held so)))
                      (assert (= (held ss) (heldAtExit)) (str "the reset release path frees every kid: held at exit " (held ss) ", pinned " (heldAtExit) " in " ss))
                      true))))))))

fn ! clean dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))]
    (do (fold (fn [(acc Bool) (n String)] -> Bool (and (ok? (pathRemove (str dir "/" n))) acc)) true names)
        (ok? (pathRemove dir))))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/perceusTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "work directory created")
        (match (rc/runtimes!)
          ((err e) (assert false (str "runtimes: " e)))
          ((ok libs) (do (assert (testMode libs dir "0") "tracing build")
                         (assert (testMode libs dir "notrace") "untraced RC build")
                         (assert (testMode libs dir "asanNotrace") "untraced RC build under ASan")
                         (assert (testIr libs dir) "reuse fires on variant, record, Option, Result and cons rebuilds and not on resized or escaping cells")
                         (assert (testCounts libs dir) "reuse hands unique cells over and leaks nothing"))))
        (assert (clean dir) "work directory removed")
        true))
