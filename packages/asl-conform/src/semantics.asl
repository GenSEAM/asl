(module aslConform/semantics
  :d "Target semantics loader and query functions for conformance verification"
  :x [loadTargetSemantics
      findRule
      findProfile
      ruleHasMutants?
      getRuleCases
      getAllRules
      getAllProfiles
      getProfiles
      getTiers]
  :i [(aslConform/types :a ty)])

(df loadTargetSemantics [] -> ty/TargetSemanticsContract
  :d "Constructs the canonical TargetSemanticsContract conforming to asl/grammar/targetSemantics.asn."
  (let [(pC11 (ty/makeProfile "c11" "C11 Native" "clang -std=c11 -Wall -Werror -fsanitize=undefined,address -fno-sanitize-recover=all -ffp-contract=off" "A"))
        (pTs (ty/makeProfile "ts" "TypeScript / Node" "tsc" "A"))
        (pPy (ty/makeProfile "py" "Python 3" "python3" "A"))
        (pWasm (ty/makeProfile "wasm" "WebAssembly WASI" "wat2wasm" "A"))
        (profiles (list pC11 pTs pPy pWasm))
        (tiers (list "A" "B" "X"))
        (mDiv1 (ty/makeMutant "divModFloorOmitMutant" "asl-target-py" "Emit native % directly without floored modulus correction" "tests/conformance/xplat/div_mod_negative"))
        (mDiv2 (ty/makeMutant "divModTruncOmitMutant" "asl-target-c" "Emit truncating division for div without sign adjustment" "tests/conformance/xplat/div_mod_negative"))
        (rDiv (ty/makeRule "divModFloor" "A" "Floored Integer Division and Modulo"
                           "div performs floor(a/b); mod performs a - b*floor(a/b)."
                           (list "tests/conformance/xplat/div_mod_positive"
                                 "tests/conformance/xplat/div_mod_negative"
                                 "tests/conformance/xplat/div_mod_pos_neg"
                                 "tests/conformance/xplat/div_mod_neg_neg"
                                 "tests/conformance/xplat/div_mod_zero_dividend"
                                 "tests/conformance/xplat/div_mod_bounds")
                           (list mDiv1 mDiv2)))
        (mShift1 (ty/makeMutant "shiftMaskOmitMutant" "asl-target-c" "Omit & 63 mask on 64-bit shift operations" "tests/conformance/xplat/shift_mask_overflow"))
        (rShift (ty/makeRule "shiftMask" "A" "Masked Bitwise Integer Shifts"
                             "Shift count right operand must be masked: & 63 for 64-bit integers and & 31 for 32-bit integers."
                             (list "tests/conformance/xplat/shift_mask_64"
                                   "tests/conformance/xplat/shift_mask_overflow")
                             (list mShift1)))
        (mWrap1 (ty/makeMutant "intWrapSignedMutant" "asl-target-c" "Perform signed addition without unsigned casting" "tests/conformance/xplat/int_wrap_add"))
        (rWrap (ty/makeRule "intWrap" "A" "Two's Complement 64-bit Integer Wrap"
                            "Integer addition, subtraction, and multiplication must wrap modulo 2^64 cleanly."
                            (list "tests/conformance/xplat/int_wrap_add"
                                  "tests/conformance/xplat/int_wrap_mul")
                            (list mWrap1)))
        (mFlt1 (ty/makeMutant "floatFormatLossyMutant" "asl-target-c" "Format floats with naive fixed 6 decimal digits precision" "tests/conformance/xplat/float_roundtrip_precision"))
        (rFlt (ty/makeRule "floatRoundtrip" "A" "Shortest IEEE 754 Float Round-Trip Formatting"
                           "Float formatting and parsing must recover exact 64-bit IEEE 754 bit pattern."
                           (list "tests/conformance/xplat/float_roundtrip_precision")
                           (list mFlt1)))
        (mOpt1 (ty/makeMutant "optionUnitNullMutant" "asl-target-py" "Collapse Option Unit directly into None under Python" "tests/conformance/xplat/option_unit_repr"))
        (rOpt (ty/makeRule "optionRepr" "A" "Option Unit Tag Preservation"
                           "Option Unit (some ()) must never collapse into None/null."
                           (list "tests/conformance/xplat/option_unit_repr"
                                 "tests/conformance/xplat/option_scalar_repr")
                           (list mOpt1)))
        (rules (list rDiv rShift rWrap rFlt rOpt))]
    (ty/makeContract 1 profiles tiers rules)))

(df findRule [(contract ty/TargetSemanticsContract) (ruleId Str)] -> (Option ty/SemanticsRule)
  :d "Finds a semantics rule by its identifier."
  (let [(matches (filter (fn [(r ty/SemanticsRule)] -> Bool (= (.-id r) ruleId)) (.-rules contract)))]
    (if (list-empty? matches) (none) (list-head matches))))

(df findProfile [(contract ty/TargetSemanticsContract) (profileId Str)] -> (Option ty/TargetProfile)
  :d "Finds an execution profile by its identifier."
  (let [(matches (filter (fn [(p ty/TargetProfile)] -> Bool (= (.-id p) profileId)) (.-profiles contract)))]
    (if (list-empty? matches) (none) (list-head matches))))

(df ruleHasMutants? [(r ty/SemanticsRule)] -> Bool
  :d "Checks if a rule carries at least one mandatory mutant."
  (> (list-length (.-mutants r)) 0))

(df getRuleCases [(r ty/SemanticsRule)] -> (List Str)
  :d "Returns list of case paths for a rule."
  (.-cases r))

(df getAllRules [(contract ty/TargetSemanticsContract)] -> (List ty/SemanticsRule)
  :d "Returns all declared rules."
  (.-rules contract))

(df getAllProfiles [(contract ty/TargetSemanticsContract)] -> (List ty/TargetProfile)
  :d "Returns all declared profiles."
  (.-profiles contract))

(df getProfiles [(contract ty/TargetSemanticsContract)] -> (List ty/TargetProfile)
  :d "Alias for getAllProfiles."
  (getAllProfiles contract))

(df getTiers [(contract ty/TargetSemanticsContract)] -> (List Str)
  :d "Returns all declared tiers."
  (.-tiers contract))

