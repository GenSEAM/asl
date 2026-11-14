(module aslBench/gen/cardLab/regrade
  :x [main]
  :i [(aslBench/gen/core :a gc)])

; (:m :ref CARD-LAB :do "regrade the first reply of every trial row of a results file with the graded cases, because before GENRUN-CROSSWIRE a check that waited on a native CLI rebuild timed out and the runner recorded it as stage check (it is an infra row now); prints one row per trial and a count per arm")

fn ! rootOf -> String
  (let [(given (optionOr (envGet "ASL_CLI_ROOT") "."))]
    (resultOr (realPath given) given))

fn ! regradeOne! cfg: gc/Config n: Int64 row: (List gc/Sx) -> String
  (let [(arm (gc/kwText row ":arm"))
        (id (gc/kwText row ":task"))
        (reply (optionOr (listHead (map (fn [(v gc/Sx)] -> String (gc/sxText v)) (gc/kwList row ":replies"))) ""))
        (dir (str cfg.work "/r" (stringFromInt64 n)))
        (made (dirCreate dir))
        (conf (fileWrite (str dir "/.asl.config.asn") "(:aslConfig :workspace \"aslBenchGenSandbox\")"))]
    (match (gc/loadTask cfg.root id)
      ((err e) (str "(:regrade :arm " (gc/asnQuote arm) " :task " (gc/asnQuote id) " :stage \"harness\" :was " (gc/kwText row ":rawPass") " :out " (gc/asnQuote e) ")"))
      ((ok t)
        (let [(g (pairFirst (gc/gradeReply! cfg dir arm t reply)))]
          (str "(:regrade :arm " (gc/asnQuote arm) " :task " (gc/asnQuote id) " :rep " (gc/kwText row ":rep") " :stage " (gc/asnQuote g.stage)
               " :was " (gc/kwText row ":rawPass") " :firstFail " (gc/asnQuote (gc/kwText row ":firstFail"))
               " :out " (gc/asnQuote (if (= g.stage "ok") "" (gc/clip g.output 240))) ")")))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(root (rootOf))
        (work (str (optionOr (envGet "TMPDIR") "/tmp") "/aslBenchGen-regrade-" (stringFromInt64 (nowNs))))
        (made (dirCreate work))
        (only (optionOr (listGet args 1) ""))
        (cfg (gc/Config :root root :aslBin (str root "/bin/asl") :work work :out "" :repairs 0 :maxTokens 0 :priceIn 0 :priceOut 0 :capPico 0 :checkFirst true))]
    (match (fileReadString (optionOr (listHead args) ""))
      ((err e) (err (str "usage: asl run asl/bench/gen/cardLab/regrade.asl RESULTS.asn [ARM]: " e)))
      ((ok text)
        (match (gc/readForms text)
          ((err e) (err e))
          ((ok forms)
            (let [(rows (filter (fn [(r (List gc/Sx))] -> Bool (or (stringEmpty? only) (= (gc/kwText r ":arm") only)))
                                (map (fn [(f gc/Sx)] -> (List gc/Sx) (gc/sxItems f))
                                     (filter (fn [(f gc/Sx)] -> Bool (= (gc/headOf f) ":trial")) forms))))
                  (done (map (fn [(i Int64)] -> String
                               (let [(line (regradeOne! cfg i (optionOr (listGet rows i) (list))))]
                                 (do (println line) line)))
                             (range 0 (listLength rows))))
                  (cleaned (gc/removeDir! work))]
              (ok 0)))))))
