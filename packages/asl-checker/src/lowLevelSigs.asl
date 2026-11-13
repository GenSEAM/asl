(module asl-checker/lowLevelSigs :x [lowLevelSig sizedIntNames conversionTarget loweredNames wrapOperatorNames unroutedName? formNames bitOperatorNames] :i [])

; (:m :ref LL-SIZED-CHECK :do "signatures of the low-level surface in one place, hooked once into types.asl#builtinSig: sized integer conversions, Wrap Clamp Checked arithmetic, integral bit operators and intrinsics, Buf operations and atomics; I is an integer-kind type variable, J a second one for shift amounts and indexes, so any sized integral type unifies and two different sized types do not")

fn sizedIntNames -> (List String)
  (list "U8" "U16" "U32" "U64" "I8" "I16")

fn conversionTarget name: String -> String
  (cond
    ((listContains? (sizedIntNames) name) name)
    ((= name "I32") "Int32")
    ((= name "I64") "Int64")
    ((= name "F64") "Float64")
    (else ""))

fn sig params: (List String) ret: String -> (Option (Pair (List String) (Pair Bool String)))
  (some (pair params (pair false ret)))

fn sigOpt params: (List String) ret: String -> (Option (Pair (List String) (Pair Bool String)))
  (some (pair params (pair true ret)))

fn overflowOpSig name: String -> (Option (Pair (List String) (Pair Bool String)))
  (cond
    ((listContains? (list "addWrap" "subWrap" "mulWrap" "addClamp" "subClamp" "mulClamp") name) (sig (list "I" "I") "I"))
    ((= name "negWrap") (sig (list "I") "I"))
    ((listContains? (list "addChecked" "subChecked" "mulChecked" "divChecked" "modChecked") name) (sig (list "I" "I") "(Option I)"))
    (else (none)))

fn bitOpSig name: String -> (Option (Pair (List String) (Pair Bool String)))
  (cond
    ((listContains? (list "&" "|" "^") name) (sig (list "I" "I") "I"))
    ((= name "~") (sig (list "I") "I"))
    ((listContains? (list "<<" ">>" "rotateLeft" "rotateRight") name) (sig (list "I" "J") "I"))
    ((= name "byteSwap") (sig (list "I") "I"))
    ((listContains? (list "bitCount" "leadingZeros" "trailingZeros") name) (sig (list "I") "Int64"))
    (else (none)))

fn bufOpSig name: String -> (Option (Pair (List String) (Pair Bool String)))
  (cond
    ((= name "bufLength") (sig (list "(Buf T)") "Int64"))
    ((= name "bufGet") (sig (list "(Buf T)" "J") "T"))
    ((= name "bufSet") (sig (list "(Buf T)" "J" "T") "Unit"))
    ((= name "bufFill") (sig (list "(Buf T)" "T") "Unit"))
    ((= name "bufCopy") (sig (list "(Buf T)" "J" "(Buf T)" "J" "J") "Unit"))
    ((= name "bufSlice") (sig (list "(Buf T)" "J" "J") "(Buf T)"))
    (else (none)))

fn atomicOpSig name: String -> (Option (Pair (List String) (Pair Bool String)))
  (cond
    ((= name "atomicLoad") (sigOpt (list "(Buf T)" "J") "T"))
    ((= name "atomicStore") (sigOpt (list "(Buf T)" "J" "T") "Unit"))
    ((listContains? (list "atomicAdd" "atomicSub" "atomicAnd" "atomicOr" "atomicXor" "atomicSwap") name) (sigOpt (list "(Buf T)" "J" "T") "T"))
    ((= name "atomicCas") (sigOpt (list "(Buf T)" "J" "T" "T") "T"))
    ((= name "fence") (sigOpt (list) "Unit"))
    (else (none)))

fn firstSome opts: (List (Option (Pair (List String) (Pair Bool String)))) -> (Option (Pair (List String) (Pair Bool String)))
  (match (listHead opts)
    ((none) (none))
    ((some o) (match o ((some s) (some s)) ((none) (firstSome (optionOr (listTail opts) (list)))))))

fn lowLevelSig name: String -> (Option (Pair (List String) (Pair Bool String)))
  (let [(target (conversionTarget name))]
    (if (stringEmpty? target)
      (firstSome (list (overflowOpSig name) (bitOpSig name) (bufOpSig name) (atomicOpSig name)))
      (sig (list "N") target)))

; (:m :ref LL-SIZED-LOWER-GAP :do "names the native target lowers today: only the integral operators, which reuse the Int64 ops; every other low-level name has a signature but no lowering until its lowering unit adds the name here, and check reports a call to it as ERR_LOWLEVEL_UNROUTED instead of leaving the build to fail")
fn bitOperatorNames -> (List String)
  (list "&" "|" "^" "~" "<<" ">>")

fn wrapOperatorNames -> (List String)
  (list "mulWrap" "addWrap" "subWrap" "rotateLeft" "rotateRight")

fn loweredNames -> (List String)
  (listAppend (bitOperatorNames) (wrapOperatorNames))

fn unroutedName? name: String -> Bool
  (and (some? (lowLevelSig name)) (not (listContains? (loweredNames) name)))

fn formNames -> (List String)
  (list "Buf" "wrap" "clamp")
