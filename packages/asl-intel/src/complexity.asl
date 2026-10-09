(module asl-intel/complexity
  :x [ComplexityMetrics ModuleComplexity analyzeComplexity! runComplexity!]
  :i [(asl-intel/text :a t)
      (asl-intel/json :a j)
      (asl-intel/tab :a tb)
      (asl-intel/host :a h)
      (asl-intel/graph :a g)])

(schema ComplexityMetrics
  (:f low Int64)
  (:f moderate Int64)
  (:f high Int64)
  (:f extreme Int64))

(schema ModuleComplexity
  (:f target String)
  (:f total Int64)
  (:f avg Float)
  (:f maxCc Int64)
  (:f hot Int64)
  (:f dist ComplexityMetrics)
  (:f fns (List g/GraphNode)))

fn rating cc: Int64 -> String
  (cond ((<= cc 5) "low") ((<= cc 15) "moderate") ((<= cc 30) "high") (else "extreme"))

fn analyzeComplexity! ctx: h/Ctx target: String limit: Int64 -> (Result ModuleComplexity String)
  (mt (g/buildGraph! ctx (g/resolveWorkspace! ctx) false)
    ((err e) (err e))
    ((ok g)
      (let [(tl (t/lowerAscii target))
            (sel (if (stringEmpty? target) g.nodes
                   (filter (fn [(n g/GraphNode)] -> Bool
                             (or (= tl (t/lowerAscii n.symbol))
                                 (or (stringContains? (t/lowerAscii n.id) tl)
                                     (or (stringContains? (t/lowerAscii n.file) tl) (stringContains? (t/lowerAscii n.module) tl)))))
                           g.nodes)))
            (ccs (map (fn [(n g/GraphNode)] -> Int64 n.complexity) sel))
            (total (listLength sel))
            (band (fn [(lo Int64) (hi Int64)] -> Int64 (listLength (filter (fn [(x Int64)] -> Bool (and (>= x lo) (<= x hi))) ccs))))
            (sorted (tb/sortWith (fn [(a g/GraphNode) (b g/GraphNode)] -> Bool (> a.complexity b.complexity)) sel))]
        (ok (ModuleComplexity :target (if (stringEmpty? target) "monorepo" target) :total total
                      :avg (if (= total 0) 0.0 (t/pyRound (/ (g/fl (fold (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) 0 ccs)) (g/fl (max 1 total))) 2))
                      :maxCc (fold (fn [(a Int64) (x Int64)] -> Int64 (max a x)) 0 ccs)
                      :hot (listLength (filter (fn [(x Int64)] -> Bool (> x 15)) ccs))
                      :dist (ComplexityMetrics :low (band -9223372036854775807 5) :moderate (band 6 15) :high (band 16 30) :extreme (band 31 9223372036854775807))
                      :fns (if (> limit 0) (t/takeN sorted limit) sorted))))))

fn formatComplexityAsn res: ModuleComplexity -> String
  (t/joinWith (list "(:moduleComplexity"
                    (str "  :target \"" res.target "\"")
                    (str "  :totalFunctions " (t/intStr res.total))
                    (str "  :avgComplexity " (t/floatStr res.avg))
                    (str "  :maxComplexity " (t/intStr res.maxCc))
                    (str "  :hotspotCount " (t/intStr res.hot))
                    (str "  :distribution (:low " (t/intStr res.dist.low) " :moderate " (t/intStr res.dist.moderate) " :high " (t/intStr res.dist.high) " :extreme " (t/intStr res.dist.extreme) ")")
                    (str "  :assertCount " (t/intStr res.total))
                    (if (listEmpty? res.fns) "  :functions []"
                      (str "  :functions [\n    "
                           (t/joinWith (map (fn [(n g/GraphNode)] -> String
                                              (t/concatAll (list "(:fn :name \"" n.symbol "\" :id \"" n.id "\" :file \"" n.file
                                                                 "\" :complexity " (t/intStr n.complexity) " :expressions " (t/intStr n.exprCount)
                                                                 " :isPure " (g/flag n.isPure) " :rating \"" (rating n.complexity) "\")")))
                                            res.fns)
                                       "\n    ")
                           "\n  ]"))
                    ")")
              "\n")

fn pct k: Int64 total: Int64 -> String
  (t/floatStr (t/pyRound (/ (g/fl (* k 100)) (g/fl (max 1 total))) 1))

fn formatComplexitySummary res: ModuleComplexity -> String
  (let [(n res.total)]
    (t/joinWith
      (listAppend
        (list (str "=== ASL FUNCTION EXECUTION COMPLEXITY AUDIT (" res.target ") ===")
              (str "Functions Scanned:   " (t/intStr n))
              (str "Average Complexity:  " (t/floatStr res.avg))
              (str "Maximum Complexity:  " (t/intStr res.maxCc))
              (str "Hotspots (>15 CC):   " (t/intStr res.hot))
              "Distribution:"
              (str "  • Low (1-5):        " (t/intStr res.dist.low) " (" (pct res.dist.low n) "%)")
              (str "  • Moderate (6-15):  " (t/intStr res.dist.moderate) " (" (pct res.dist.moderate n) "%)")
              (str "  • High (16-30):     " (t/intStr res.dist.high) " (" (pct res.dist.high n) "%)")
              (str "  • Extreme (>30):    " (t/intStr res.dist.extreme) " (" (pct res.dist.extreme n) "%)"))
        (if (listEmpty? res.fns) (list)
          (cons "" (cons (str "--- Top Complex Functions (Showing " (t/intStr (listLength res.fns)) ") ---")
            (listReverse (pairSecond (fold (fn [(acc (Pair Int64 (List String))) (f g/GraphNode)] -> (Pair Int64 (List String))
                                             (pair (+ (pairFirst acc) 1)
                                                   (cons (str "     Source: " f.file)
                                                         (cons (t/concatAll (list "  " (t/intStr (pairFirst acc)) ". " f.id " [CC: " (t/intStr f.complexity)
                                                                                  ", Exprs: " (t/intStr f.exprCount) ", " (if f.isPure "pure" "impure(!)")
                                                                                  ", Rating: " (rating f.complexity) "]"))
                                                               (pairSecond acc)))))
                                           (pair 1 (list)) res.fns)))))))
      "\n"))

fn complexityJson res: ModuleComplexity -> j/Json
  (j/jObj (list (pair "status" (j/jStr "ok")) (pair "target" (j/jStr res.target)) (pair "totalFunctions" (j/jInt res.total))
                (pair "avgComplexity" (j/jFloat res.avg)) (pair "maxComplexity" (j/jInt res.maxCc)) (pair "hotspotCount" (j/jInt res.hot))
                (pair "distribution" (j/jObj (list (pair "low" (j/jInt res.dist.low)) (pair "moderate" (j/jInt res.dist.moderate))
                                                   (pair "high" (j/jInt res.dist.high)) (pair "extreme" (j/jInt res.dist.extreme)))))
                (pair "functions" (j/jArr (map (fn [(f g/GraphNode)] -> j/Json
                                                 (j/jObj (list (pair "name" (j/jStr f.symbol)) (pair "id" (j/jStr f.id)) (pair "file" (j/jStr f.file))
                                                               (pair "module" (j/jStr f.module)) (pair "cyclomaticComplexity" (j/jInt f.complexity))
                                                               (pair "expressionCount" (j/jInt f.exprCount)) (pair "isPure" (j/jBool f.isPure))
                                                               (pair "rating" (j/jStr (rating f.complexity))))))
                                               res.fns)))))

fn runComplexity! ctx: h/Ctx fmt: String target: String limit: Int64 -> h/Outcome
  (mt (analyzeComplexity! ctx target limit)
    ((err e) (h/outcome "" (str "Error: " e "\n") 1))
    ((ok res) (h/outcome (str (cond ((= fmt "json") (j/dumps (complexityJson res))) ((= fmt "summary") (formatComplexitySummary res)) (else (formatComplexityAsn res))) "\n") "" 0)))
