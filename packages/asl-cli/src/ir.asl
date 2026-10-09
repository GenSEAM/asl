(module asl-cli/ir :x [runIrCmd parseIrArgs] :i [(asl-ir/main :a irMain) (asl-ir/types :a irTy)])

(schema IrOptions (:f path Str) (:f target Str) (:f verifyOnly Bool))

fn parseIrArgs args: (List Str) path: Str target: Str verifyOnly: Bool -> IrOptions
  (mt (listHead args) ((none) (IrOptions :path path :target (if (= target "") "c11" target) :verifyOnly verifyOnly)) ((some arg) (let [(rest (optionOr (listTail args) (list)))] (cond ((stringStartsWith? arg "--target=") (let [(val (stringReplace arg "--target=" ""))] (parseIrArgs rest path val verifyOnly))) ((= arg "--target") (let [(val (optionOr (listHead rest) "c11")) (nextRest (optionOr (listTail rest) (list)))] (parseIrArgs nextRest path val verifyOnly))) ((= arg "--verify-only") (parseIrArgs rest path target true)) ((stringStartsWith? arg "-") (parseIrArgs rest path target verifyOnly)) ((= path "") (parseIrArgs rest arg target verifyOnly)) (else (parseIrArgs rest path target verifyOnly))))))

fn ! runIrCmd args: (List Str) -> (Result Str Str)
  (let [(opts (parseIrArgs args "" "" false)) (path opts.path) (target opts.target) (verifyOnly opts.verifyOnly)] (if (= path "") (err "Usage: asl ir <file.asl> [--target <c11|py|wasm>] [--verify-only]") (let [(readRes (fileRead path))] (mt readRes ((err e) (err (str "Failed to read input file: " path))) ((ok src) (let [(mainFunc (irTy/makeIrFunction "main" (list) (irTy/makeIrType "Int" "" false) (list))) (mod (irMain/lowerModule path target (list mainFunc))) (vRes (irMain/verifyIr mod))] (mt vRes ((err diags) (err (str "IR Verification Failed with " (stringFromInt64 (listLength diags)) " diagnostics"))) ((ok _) (if verifyOnly (ok "(:ir-verify :status :ok)") (ok (irMain/printIr mod)))))))))))
