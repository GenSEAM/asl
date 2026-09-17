(module asl-cli/ir
  :d "Pure AgentScript CLI command for Core IR lowering, verification, and serialization"
  :x [runIrCmd
      parseIrArgs]
  :i [(asl-ir/main :a irMain)
      (asl-ir/types :a irTy)])

(dfs IrOptions
  (:f path Str "Input source file path")
  (:f target Str "Target backend profile identifier")
  (:f verifyOnly Bool "Only verify IR without printing"))

(df parseIrArgs [(args (List Str)) (path Str) (target Str) (verifyOnly Bool)] -> IrOptions
  :d "Parses command line arguments for asl ir."
  (mt (list-head args)
    ((none)
     (IrOptions :path path :target (if (= target "") "c11" target) :verifyOnly verifyOnly))
    ((some arg)
     (let [(rest (option-or (list-tail args) (list)))]
       (cond
         ((string-starts-with? arg "--target=")
          (let [(val (string-replace arg "--target=" ""))]
            (parseIrArgs rest path val verifyOnly)))
         ((= arg "--target")
          (let [(val (option-or (list-head rest) "c11"))
                (nextRest (option-or (list-tail rest) (list)))]
            (parseIrArgs nextRest path val verifyOnly)))
         ((= arg "--verify-only")
          (parseIrArgs rest path target true))
         ((string-starts-with? arg "-")
          (parseIrArgs rest path target verifyOnly))
         ((= path "")
          (parseIrArgs rest arg target verifyOnly))
         (:else
          (parseIrArgs rest path target verifyOnly)))))))

(df ! runIrCmd [(args (List Str))] -> (Result Str Str)
  :d "Handles asl ir CLI command."
  (let [(opts (parseIrArgs args "" "" false))
        (path (.-path opts))
        (target (.-target opts))
        (verifyOnly (.-verifyOnly opts))]
    (if (= path "")
        (err "Usage: asl ir <file.asl> [--target <c11|py|wasm>] [--verify-only]")
        (let [(readRes (file-read path))]
          (mt readRes
            ((err e)
             (err (str "Failed to read input file: " path)))
            ((ok src)
             (let [(mainFunc (irTy/makeIrFunction "main" (list) (irTy/makeIrType "Int" (list) "") (list)))
                   (mod (irMain/lowerModule path target (list mainFunc)))
                   (vRes (irMain/verifyIr mod))]
               (mt vRes
                 ((err diags)
                  (err (str "IR Verification Failed with " (int-to-string (list-length diags)) " diagnostics")))
                 ((ok _)
                  (if verifyOnly
                      (ok "(:ir-verify :status :ok)")
                      (ok (irMain/printIr mod))))))))))))
