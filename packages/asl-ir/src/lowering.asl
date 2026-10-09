(module asl-ir/lowering :x [assignOptionRepr lowerMatchToSwitch lowerTailRecursion] :i [(asl-ir/types :a ty)])

fn assignOptionRepr profileId: Str innerType: Str -> Str
  (let [(t (stringLower innerType))] (cond ((= t "unit") "tagged") ((or (stringStartsWith? t "option") (= t "option")) "tagged") ((= profileId "c11") (if (or (= t "str") (= t "buf") (= t "closure")) "nullable" "tagged")) ((= profileId "wasm") "tagged") ((= profileId "py") (if (or (= t "unit") (stringStartsWith? t "option") (= t "option")) "tagged" "nullable")) ((= profileId "ts") (if (or (= t "unit") (stringStartsWith? t "option") (= t "option")) "tagged" "nullable")) (else "tagged")))

fn lowerMatchToSwitch scrutinee: Str cases: (List ty/IrSwitchCase) defaultBody: (List Any) -> ty/IrStmt
  (ty/makeIrSwitch scrutinee cases defaultBody)

fn lowerTailRecursion f: ty/IrFunction -> ty/IrFunction
  f
