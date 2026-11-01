(module asl-intel/tests/modRankTest :x [runTests] :i [(asl-intel/graph :a g) (asl-intel/host :a h) (asl-intel/text :a t)])

fn modText m: String -> String
  (str "(module " m "\n  :x [shared]\n  :i [])\n\nfn shared n: Int64 -> Int64\n  n\n")

fn callerText -> String
  "(module caller\n  :x [go]\n  :i [(zeta :a zt) (eta :a et)])\n\nfn go n: Int64 -> Int64\n  (et/shared n)\n"

fn fanOf gr: g/Graph m: String -> Int64
  (match (listHead (filter (fn [(n g/GraphNode)] -> Bool (and (= n.module m) (= n.symbol "shared"))) gr.nodes))
    ((some n) n.fanIn)
    ((none) -1))

; (:m :ref INTEL-PARITY-RED-20261031 :do "a call to a symbol two imports define goes to the module with the smaller name, not the earlier file")
fn ! runTests -> Bool
  (let [(base (t/joinPath "/tmp" (str "modrank" (t/intStr (procSelf)))))
        (ctx (h/Ctx :home base :cwd base :aslRoot "" :env (some (list "PATH=/usr/bin:/bin" "GIT_CONFIG_NOSYSTEM=1"))))
        (w1 (dirCreate base))
        (w2 (fileWrite (t/joinPath base "z.asl") (modText "eta")))
        (w3 (fileWrite (t/joinPath base "a.asl") (modText "zeta")))
        (w4 (fileWrite (t/joinPath base "m.asl") (callerText)))
        (g1 (h/runCapture! ctx (list "git" "-c" "init.defaultBranch=main" "init" "-q") (some base)))
        (g2 (h/runCapture! ctx (list "git" "add" "-A") (some base)))
        (built (g/buildGraph! ctx base false))
        (gone (pathRemove base))]
    (match built
      ((err e) (do (eprintln e) (assert (stringEmpty? e) "graph builds") false))
      ((ok gr)
        (do
          (assert (match w2 ((ok _) true) ((err _) false)) "eta module written to the later file z.asl")
          (assert (match g2 ((ok r) (= r.code 0)) ((err _) false)) "git add ran")
          (assert (= (fanOf gr "eta") 1) "the call resolves to eta (smaller name) although zeta's file a.asl is scanned first")
          (assert (= (fanOf gr "zeta") 0) "zeta gets no caller")
          true))))
