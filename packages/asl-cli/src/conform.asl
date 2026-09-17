(module asl-cli/conform
  :d "Pure AgentScript CLI runner for cross-platform target conformance suite"
  :x [runConformCmd
      parseConformArgs]
  :i [(aslConform/main :a conf)])

(dfs ConformOptions
  (:f profile Str "Target profile identifier")
  (:f rule Str "Target rule filter")
  (:f invert Bool "Inverted assertion reachability mode"))

(df parseConformArgs [(args (List Str)) (profile Str) (rule Str) (invert Bool)] -> ConformOptions
  :d "Parses command line arguments for asl conform."
  (mt (list-head args)
    ((none)
     (ConformOptions :profile (if (= profile "") "py" profile) :rule rule :invert invert))
    ((some flag)
     (let [(rest (option-or (list-tail args) (list)))]
       (cond
         ((string-starts-with? flag "--profile=")
          (let [(val (string-replace flag "--profile=" ""))]
            (parseConformArgs rest val rule invert)))
         ((= flag "--profile")
          (let [(val (option-or (list-head rest) "py"))
                (nextRest (option-or (list-tail rest) (list)))]
            (parseConformArgs nextRest val rule invert)))
         ((string-starts-with? flag "--rule=")
          (let [(val (string-replace flag "--rule=" ""))]
            (parseConformArgs rest profile val invert)))
         ((= flag "--rule")
          (let [(val (option-or (list-head rest) ""))
                (nextRest (option-or (list-tail rest) (list)))]
            (parseConformArgs nextRest profile val invert)))
         ((= flag "--invert")
          (parseConformArgs rest profile rule true))
         (:else
          (parseConformArgs rest profile rule invert)))))))

(df ! runConformCmd [(args (List Str))] -> (Result Str Str)
  :d "Handles asl conform CLI command."
  (let [(opts (parseConformArgs args "" "" false))
        (profile (.-profile opts))
        (rule (.-rule opts))
        (invert (.-invert opts))]
    (conf/runConform profile rule invert)))
