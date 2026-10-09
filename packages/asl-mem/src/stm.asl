(module aslMem/stm :x [STMFileSnapshot STMTransaction STMCommitResult stmBegin stmRead stmWrite! stmRollback stmValidateAndMerge stmGetSnapshot stmDirtyFiles stmRebase] :i [(astMerge :a am) (vfs :a v)])

(schema ASTCollisionRecord (:f symbolId Str) (:f baseForm Str) (:f branchA Str) (:f branchB Str) (:f collisionType Str))

(schema AstMergeResult (:f mergedContent Str) (:f conflicts (List Str)) (:f collisions (List ASTCollisionRecord)) (:f clean Bool) (:f mergedFormsCount I64))

(schema STMFileSnapshot (:f path Str) (:f baseContent Str) (:f stagedContent Str) (:f baseHash Str) (:f dirty Bool))

(schema STMTransaction (:f txId Str) (:f agentId Str) (:f epoch I64) (:f snapshots (List STMFileSnapshot)) (:f status Str) (:f compensations (List Str)))

(schema STMCommitResult (:f txId Str) (:f committed Bool) (:f touchedFiles (List Str)) (:f conflictedFiles (List Str)) (:f reconciledFiles (List Str)) (:f mergedContents (List Str)) (:f errorMessage (Option Str)))

fn stmBegin txId: Str agentId: Str epoch: I64 -> STMTransaction
  (STMTransaction :txId txId :agentId agentId :epoch epoch :snapshots (list) :status "active" :compensations (list))

fn stmGetSnapshot tx: STMTransaction targetPath: Str -> (Option STMFileSnapshot)
  (fold (fn [(acc (Option STMFileSnapshot)) (s STMFileSnapshot)] -> (Option STMFileSnapshot) (mt acc ((some found) (some found)) ((none) (if (= s.path targetPath) (some s) (none))))) (none) tx.snapshots)

fn stmRead tx: STMTransaction path: Str currentTrunk: Str -> STMTransaction
  (let [(existing (stmGetSnapshot tx path))] (mt existing ((some _) tx) ((none) (let [(snap (STMFileSnapshot :path path :baseContent currentTrunk :stagedContent currentTrunk :baseHash (v/vfsCasHash currentTrunk) :dirty false)) (nextSnaps (listAppend tx.snapshots (list snap)))] (with tx :snapshots nextSnaps)))))

fn stmWrite! tx: STMTransaction path: Str newContent: Str -> STMTransaction
  (let [(snaps tx.snapshots) (existing (stmGetSnapshot tx path))] (mt existing ((some curr) (let [(updated (STMFileSnapshot :path path :baseContent curr.baseContent :stagedContent newContent :baseHash curr.baseHash :dirty true)) (nextSnaps (fold (fn [(acc (List STMFileSnapshot)) (s STMFileSnapshot)] -> (List STMFileSnapshot) (if (= s.path path) (listAppend acc (list updated)) (listAppend acc (list s)))) (list) snaps))] (with tx :snapshots nextSnaps))) ((none) (let [(base (if (fileExists? path) (mt (fileRead path) ((ok c) c) ((err _) "")) "")) (bHash (v/vfsCasHash base)) (snap (STMFileSnapshot :path path :baseContent base :stagedContent newContent :baseHash bHash :dirty true)) (nextSnaps (listAppend snaps (list snap)))] (with tx :snapshots nextSnaps)))))

fn stmRollback tx: STMTransaction reason: Str -> STMTransaction
  (with tx :status "aborted" :compensations (listAppend tx.compensations (list reason)))

fn stmDirtyFiles tx: STMTransaction -> (List Str)
  (fold (fn [(acc (List Str)) (s STMFileSnapshot)] -> (List Str) (if s.dirty (listAppend acc (list s.path)) acc)) (list) tx.snapshots)

fn findTrunkContent paths: (List Str) contents: (List Str) target: Str -> (Option Str)
  (let [(idxOpt (fold (fn [(acc (Option I64)) (p Str)] -> (Option I64) (mt acc ((some found) (some found)) ((none) (if (= p target) (some 0) (none))))) (none) paths))] (mt idxOpt ((none) (none)) ((some _) (let [(res (fold (fn [(acc (Option Str)) (pair Str)] -> (Option Str) (mt acc ((some found) (some found)) ((none) (if (stringStartsWith? pair (str target ":")) (some (let [(pref (str target ":")) (plen (stringLength pref))] (optionOr (stringSlice pair plen (stringLength pair)) ""))) (none))))) (none) contents))] res))))

(schema OCCValidationAccumulator (:f touched (List Str)) (:f conflicts (List Str)) (:f reconciled (List Str)) (:f mergedTexts (List Str)) (:f ok Bool))

fn stmValidateAndMerge tx: STMTransaction trunkPaths: (List Str) trunkContents: (List Str) -> STMCommitResult
  (let [(snaps tx.snapshots) (init (OCCValidationAccumulator :touched (list) :conflicts (list) :reconciled (list) :mergedTexts (list) :ok true)) (res (fold (fn [(acc OCCValidationAccumulator) (s STMFileSnapshot)] -> OCCValidationAccumulator (if (not s.dirty) acc (let [(p s.path) (baseTxt s.baseContent) (stagedTxt s.stagedContent) (trunkOpt (findTrunkContent trunkPaths trunkContents p)) (curTrunk (optionOr trunkOpt baseTxt)) (touched (listAppend acc.touched (list p)))] (if (= curTrunk baseTxt) (OCCValidationAccumulator :touched touched :conflicts acc.conflicts :reconciled acc.reconciled :mergedTexts (listAppend acc.mergedTexts (list stagedTxt)) :ok acc.ok) (let [(isAst (or (stringEndsWith? p ".asl") (stringEndsWith? p ".asn"))) (mergeRes (if isAst (am/universalAst3wayMerge baseTxt stagedTxt curTrunk) (if (= stagedTxt curTrunk) (AstMergeResult :mergedContent stagedTxt :conflicts (list) :collisions (list) :clean true :mergedFormsCount 1) (AstMergeResult :mergedContent stagedTxt :conflicts (list p) :collisions (list) :clean false :mergedFormsCount 0))))] (if mergeRes.clean (OCCValidationAccumulator :touched touched :conflicts acc.conflicts :reconciled (listAppend acc.reconciled (list p)) :mergedTexts (listAppend acc.mergedTexts (list mergeRes.mergedContent)) :ok acc.ok) (OCCValidationAccumulator :touched touched :conflicts (listAppend acc.conflicts (list p)) :reconciled acc.reconciled :mergedTexts acc.mergedTexts :ok false))))))) init snaps))] (if res.ok (STMCommitResult :txId tx.txId :committed true :touchedFiles res.touched :conflictedFiles (list) :reconciledFiles res.reconciled :mergedContents res.mergedTexts :errorMessage (none)) (STMCommitResult :txId tx.txId :committed false :touchedFiles res.touched :conflictedFiles res.conflicts :reconciledFiles res.reconciled :mergedContents (list) :errorMessage (some "OCC transaction aborted: AST collision on concurrent trunk write"))))

fn stmRebase tx: STMTransaction trunkPaths: (List Str) trunkContents: (List Str) -> STMTransaction
  (let [(snaps tx.snapshots) (nextSnaps (fold (fn [(acc (List STMFileSnapshot)) (s STMFileSnapshot)] -> (List STMFileSnapshot) (let [(p s.path) (trunkOpt (findTrunkContent trunkPaths trunkContents p)) (curTrunk (optionOr trunkOpt s.baseContent))] (if (= curTrunk s.baseContent) (listAppend acc (list s)) (let [(isAst (or (stringEndsWith? p ".asl") (stringEndsWith? p ".asn"))) (mergeRes (if isAst (am/universalAst3wayMerge s.baseContent s.stagedContent curTrunk) (AstMergeResult :mergedContent s.stagedContent :conflicts (list) :collisions (list) :clean false :mergedFormsCount 0)))] (if mergeRes.clean (listAppend acc (list (STMFileSnapshot :path p :baseContent curTrunk :stagedContent mergeRes.mergedContent :baseHash (v/vfsCasHash curTrunk) :dirty (not (= curTrunk mergeRes.mergedContent))))) (listAppend acc (list s))))))) (list) snaps))] (with tx :snapshots nextSnaps))
