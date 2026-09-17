(module asl-ir/main
  :d "Top-level API for AgentScript Core IR lowering, verification, printing, and AST patching"
  :x [lowerModule
      verifyIr
      printIr
      compileToIr
      assignOptionRepr
      parsePatch
      applyPatch
      invertPatch
      verifyPatch
      makeReplacePatch]
  :i [(asl-ir/types :a ty)
      (asl-ir/anf :a anf)
      (asl-ir/lowering :a low)
      (asl-ir/drops :a drp)
      (asl-ir/verify :a vfy)
      (asl-ir/printer :a prn)
      (asl-ir/patch :a patch)])

(df assignOptionRepr [(profileId Str) (innerType Str)] -> Str
  :d "Assigns representation for Option type under designated profile."
  (low/assignOptionRepr profileId innerType))

(df lowerModule [(name Str) (profileId Str) (funcs (List ty/IrFunction))] -> ty/IrModule
  :d "Constructs an IrModule and runs drop insertion and ANF normalization."
  (let [(normFuncs (map (fn [(f ty/IrFunction)] -> ty/IrFunction
                          (ty/makeIrFunction (.-name f)
                                             (.-params f)
                                             (.-retType f)
                                             (drp/insertDrops (anf/toAnf (.-body f)))))
                        funcs))]
    (ty/makeIrModule name profileId normFuncs)))

(df verifyIr [(m ty/IrModule)] -> (Result Unit (List ty/IrDiag))
  :d "Verifies an entire IR module."
  (vfy/verifyIr m))

(df printIr [(m ty/IrModule)] -> Str
  :d "Prints an IR module as ASN text."
  (prn/printIr m))

(df compileToIr [(modName Str) (profileId Str) (funcs (List ty/IrFunction))] -> (Result Str (List ty/IrDiag))
  :d "Lowers, verifies, and serializes an IR module."
  (let [(m (lowerModule modName profileId funcs))
        (vRes (verifyIr m))]
    (mt vRes
      ((ok _) (ok (printIr m)))
      ((err diags) (err diags)))))

(df parsePatch [(patchText Str)] -> (Result patch/AstPatch patch/PatchDiag)
  :d "Parses an AST patch from ASN text."
  (patch/parsePatch patchText))

(df applyPatch [(p patch/AstPatch) (sourceCode Str)] -> patch/PatchResult
  :d "Applies an AST patch to source code with fail-closed in-memory roundtrip validation."
  (patch/applyPatch p sourceCode))

(df invertPatch [(p patch/AstPatch)] -> patch/AstPatch
  :d "Generates the inverse AST patch for transactional rollback."
  (patch/invertPatch p))

(df verifyPatch [(p patch/AstPatch) (sourceCode Str)] -> (Result Unit (List patch/PatchDiag))
  :d "Verifies whether an AST patch applies cleanly without committing."
  (patch/verifyPatch p sourceCode))

(df makeReplacePatch [(id Str) (targetModule Str) (targetSymbol Str) (anchor Str) (oldNode Str) (newNode Str)] -> patch/AstPatch
  :d "Constructs a single-op replace AST patch."
  (patch/makeReplacePatch id targetModule targetSymbol anchor oldNode newNode))
