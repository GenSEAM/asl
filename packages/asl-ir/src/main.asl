(module asl-ir/main :x [lowerModule verifyIr printIr compileToIr assignOptionRepr parsePatch applyPatch invertPatch verifyPatch makeReplacePatch] :i [(asl-ir/types :a ty) (asl-ir/anf :a anf) (asl-ir/lowering :a low) (asl-ir/drops :a drp) (asl-ir/verify :a vfy) (asl-ir/printer :a prn) (asl-ir/patch :a patch)])

fn assignOptionRepr profileId: Str innerType: Str -> Str
  (low/assignOptionRepr profileId innerType)

fn lowerModule name: Str profileId: Str funcs: (List ty/IrFunction) -> ty/IrModule
  (let [(normFuncs (map (fn [(f ty/IrFunction)] -> ty/IrFunction (ty/makeIrFunction f.name f.params f.retType (drp/insertDrops (anf/toAnf f.body)))) funcs))] (ty/makeIrModule name profileId normFuncs))

fn verifyIr m: ty/IrModule -> (Result Unit (List ty/IrDiag))
  (vfy/verifyIr m)

fn printIr m: ty/IrModule -> Str
  (prn/printIr m)

fn compileToIr modName: Str profileId: Str funcs: (List ty/IrFunction) -> (Result Str (List ty/IrDiag))
  (let [(m (lowerModule modName profileId funcs)) (vRes (verifyIr m))] (mt vRes ((ok _) (ok (printIr m))) ((err diags) (err diags))))

fn parsePatch patchText: Str -> (Result patch/AstPatch patch/PatchDiag)
  (patch/parsePatch patchText)

fn applyPatch p: patch/AstPatch sourceCode: Str -> patch/PatchResult
  (patch/applyPatch p sourceCode)

fn invertPatch p: patch/AstPatch -> patch/AstPatch
  (patch/invertPatch p)

fn verifyPatch p: patch/AstPatch sourceCode: Str -> (Result Unit (List patch/PatchDiag))
  (patch/verifyPatch p sourceCode)

fn makeReplacePatch id: Str targetModule: Str targetSymbol: Str anchor: Str oldNode: Str newNode: Str -> patch/AstPatch
  (patch/makeReplacePatch id targetModule targetSymbol anchor oldNode newNode)
