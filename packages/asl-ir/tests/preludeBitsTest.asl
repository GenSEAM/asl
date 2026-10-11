(module asl-ir/tests/preludeBitsTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/printer :a prn)
      (asl-ir/lower :a low)
      (asl-ir/link :a lk)])

fn printed res: (Result ty/SsaModule (List ty/IrDiag)) -> String
  (mt res
    ((ok m) (prn/printSsa m))
    ((err ds) (str "lower failed: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.locus ": " d.message)) ds) "; "))))

fn lowerOnly unit: lk/LinkUnit names: (List String) -> String
  (printed (low/lowerLinked unit.forms unit.positions (low/LinkScope :path unit.path :imports (mapEmpty) :prelude (list) :strings (list) :only (some names))))

fn ! preludeUnit! -> (Result lk/LinkUnit String)
  (mt (lk/loadClosure! (lk/preludePath))
    ((err ds) (err (stringJoin (map (fn [(d ty/IrDiag)] -> String d.message) ds) "; ")))
    ((ok units) (mt (listHead units) ((some u) (ok u)) ((none) (err "prelude closure is empty")))))

fn withOverlay prelude: lk/LinkUnit o: lk/LinkUnit -> lk/LinkUnit
  (lk/LinkUnit :path prelude.path :name prelude.name :forms (listAppend prelude.forms (optionOr (listTail o.forms) (list))) :positions prelude.positions :imports prelude.imports)

fn ! bareOp text: String fnName: String prim: String helper: String -> Bool
  (let [(start (optionOr (stringIndexOf text (str "(fn prelude." fnName " ")) -1))
        (body (if (< start 0) "" (optionOr (stringSlice text start (stringLength text)) "")))]
    (do
      (assert (>= start 0) (str "prelude." fnName " is lowered:\n" text))
      (assert (stringContains? body (str "(prim " prim " ")) (str "prelude." fnName " is one " prim " instruction:\n" body))
      (refute (stringContains? text (str "(call prelude." helper)) (str "prelude." fnName " calls no per-bit " helper ":\n" text))
      (refute (stringContains? text (str "(call prelude." fnName " ")) (str "prelude." fnName " does not call itself:\n" text))
      true))

fn ! testOperatorBodies prelude: lk/LinkUnit -> Bool
  (let [(text (lowerOnly prelude (list "&" "|" "^" "~")))]
    (do
      (bareOp text "&" "rawAndI64" "preludeAndBits")
      (bareOp text "|" "rawOrI64" "preludeOrBits")
      (bareOp text "^" "rawXorI64" "preludeXorBits")
      (bareOp text "~" "rawXorI64" "preludeLow")
      true))

fn ! testOverlayCallSites prelude: lk/LinkUnit -> Bool
  (mt (lk/overlayUnit!)
    ((err ds) (do (assert false (str "native overlay loads: " (stringJoin (map (fn [(d ty/IrDiag)] -> String d.message) ds) "; "))) false))
    ((ok o) (let [(text (lowerOnly (withOverlay prelude o) (list "bigSigma0" "choose" "majority" "rotr" "shrWord" "shlWord" "mask32")))]
              (do
                (assert (stringContains? text "(prim rawXorI64 ") (str "sha256 xor is an instruction inside the prelude:\n" text))
                (assert (stringContains? text "(prim rawAndI64 ") (str "sha256 and is an instruction inside the prelude:\n" text))
                (assert (stringContains? text "(prim rawOrI64 ") (str "sha256 or is an instruction inside the prelude:\n" text))
                (assert (stringContains? text "(prim rawAshrI64 ") (str "shrWord is one shift:\n" text))
                (assert (stringContains? text "(prim rawShlI64 ") (str "shlWord is one shift:\n" text))
                (map (fn [(op String)] -> Bool (do (refute (stringContains? text (str "(call prelude." op " ")) (str "no call of prelude." op " from the overlay:\n" text)) true))
                     (list "&" "|" "^" "pow2"))
                true))))

fn ! testUserShadow -> Bool
  (let [(src (stringJoin (list "(module shadowBits :x [main ^] :i [])"
                               "fn ^ a: Int64 b: Int64 -> Int64"
                               "  (+ a b)"
                               "fn main -> Int64"
                               "  (^ 1 2)") "\n"))
        (text (printed (low/lowerSource src)))]
    (do
      (assert (stringContains? text "(call ^ ") (str "a module's own ^ still wins over the instruction:\n" text))
      (refute (stringContains? text "rawXorI64") (str "a module's own ^ is not an xor:\n" text))
      true))

fn ! runTests -> Bool
  (mt (preludeUnit!)
    ((err e) (do (assert false (str "prelude loads: " e)) false))
    ((ok prelude) (do (testOperatorBodies prelude) (testOverlayCallSites prelude) (testUserShadow) true)))
