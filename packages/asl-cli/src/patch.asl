(module asl-cli/patch
  :d "Pure ASL CLI patch command handler, Merkle optimistic concurrency, and LIFO rollback stack."
  :x [RollbackEntry makeRollbackEntry
      runPatchCommand
      validateMerkleRoot
      pushRollbackStack
      popRollbackStack
      checkDisjointCommutativity
      executePatchApply
      executePatchCheck
      executePatchRollback
      parsePatchStackFile
      renderPatchStackFile]
  :i [(asl-ir/patch :a patch)
      (asl-parser/ast :a ast)
      (asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)])

(dfs RollbackEntry
  (:f patchId Str "Identifier of applied patch")
  (:f targetFile Str "Target file path on disk")
  (:f targetModule Str "Target module identifier")
  (:f preRoot Str "AST Merkle digest before patch application")
  (:f postRoot Str "AST Merkle digest after patch application")
  (:f inversePatch patch/AstPatch "Inverse patch structure for rollback")
  (:f timestamp Int64 "Epoch timestamp of application"))

(df makeRollbackEntry [(patchId Str) (targetFile Str) (targetModule Str) (preRoot Str) (postRoot Str) (inv patch/AstPatch) (timestamp Int64)] -> RollbackEntry
  :d "Constructs a RollbackEntry record."
  (RollbackEntry :patchId patchId :targetFile targetFile :targetModule targetModule :preRoot preRoot :postRoot postRoot :inversePatch inv :timestamp timestamp))

(df validateMerkleRoot [(expected Str) (actual Str)] -> Bool
  :d "Validates that the expected Merkle root digest matches actual root."
  (or (string-empty? expected)
      (= expected actual)))

(df getOpAnchorKey [(op patch/AstPatchOp)] -> Str
  :d "Builds a composite qualified anchor key Module:symbol/anchor."
  (mt op
    ((patch/patchOpReplace target anchor _ _) (str target "/" anchor))
    ((patch/patchOpSplice target anchor _ _ _) (str target "/" anchor))
    ((patch/patchOpRename target _ _) (str target "/rename"))
    ((patch/patchOpRetype target anchor _ _) (str target "/" anchor))))

(df checkDisjointCommutativity [(p1 patch/AstPatch) (p2 patch/AstPatch)] -> Bool
  :d "Verifies whether two candidate patches target non-overlapping AST subtree anchor paths."
  (let [(anchors1 (map (fn [(op patch/AstPatchOp)] -> Str (getOpAnchorKey op)) (.-ops p1)))
        (anchors2 (map (fn [(op patch/AstPatchOp)] -> Str (getOpAnchorKey op)) (.-ops p2)))
        (overlap (fold (fn [(acc Bool) (a1 Str)] -> Bool
                         (or acc (fold (fn [(subAcc Bool) (a2 Str)] -> Bool
                                         (or subAcc (= a1 a2)))
                                       false
                                       anchors2)))
                       false
                       anchors1))]
    (not overlap)))

(df unquoteText [(s Str)] -> Str
  :d "Strips enclosing quotes from a string literal if present."
  (let [(len (string-length s))]
    (if (and (>= len 2)
             (string-starts-with? s "\"")
             (string-ends-with? s "\""))
        (option-or (string-slice s 1 (- len 1)) "")
        s)))

(df findKvAtom [(items (List rd/SExpr)) (key Str)] -> Str
  :d "Finds atom value following keyword key in SExpr list."
  (mt (list-head items)
    ((some it)
     (let [(rest (option-or (list-tail items) (list)))]
       (if (and (rd/isAtom? it) (= (rd/sexprHead it) key))
           (mt (list-head rest)
             ((some valNode) (unquoteText (rd/sexprHead valNode)))
             ((none) ""))
           (findKvAtom rest key))))
    ((none) "")))

(df findKvNode [(items (List rd/SExpr)) (key Str)] -> (Option rd/SExpr)
  :d "Finds node value following keyword key in SExpr list."
  (mt (list-head items)
    ((some it)
     (let [(rest (option-or (list-tail items) (list)))]
       (if (and (rd/isAtom? it) (= (rd/sexprHead it) key))
           (list-head rest)
           (findKvNode rest key))))
    ((none) (none))))

(df parseRollbackEntryNode [(form rd/SExpr)] -> (Option RollbackEntry)
  :d "Parses a single RollbackEntry form from SExpr."
  (mt form
    ((rd/sexprList items)
     (let [(head (mt (list-head items) ((some h) (rd/sexprHead h)) ((none) "")))]
       (if (and (!= head ":rollbackEntry") (!= head "rollbackEntry"))
           (none)
           (let [(patchId (findKvAtom items ":patchId"))
                 (targetFile (findKvAtom items ":targetFile"))
                 (targetModule (findKvAtom items ":targetModule"))
                 (preRoot (findKvAtom items ":preRoot"))
                 (postRoot (findKvAtom items ":postRoot"))
                 (timeStr (findKvAtom items ":timestamp"))
                 (ts (option-or (string-to-int64 timeStr) 0))
                 (invOpt (findKvNode items ":inversePatch"))]
             (mt invOpt
               ((none) (none))
               ((some invNode)
                (let [(invText (rd/renderSexpr invNode))
                      (parsedInvRes (patch/parsePatch invText))]
                  (mt parsedInvRes
                    ((ok invPatch)
                     (some (makeRollbackEntry patchId targetFile targetModule preRoot postRoot invPatch ts)))
                    ((err _) (none))))))))))
    (_ (none))))

(df parsePatchStackFile [(content Str)] -> (List RollbackEntry)
  :d "Parses .asl/mem/patch_stack.asn content into a list of RollbackEntry records."
  (if (string-empty? (string-trim content))
      (list)
      (let [(toks (lx/tokenize content))
            (readRes (ast/readForms toks))]
        (mt readRes
          ((err _) (list))
          ((ok forms)
           (mt (list-head forms)
             ((none) (list))
             ((some pf)
              (mt (.-expr pf)
                ((rd/sexprList items)
                 (let [(entriesOpt (findKvNode items ":entries"))]
                   (mt entriesOpt
                     ((none) (list))
                     ((some eNode)
                      (let [(entryForms (mt eNode
                                          ((rd/sexprVect v) v)
                                          ((rd/sexprList l) l)
                                          (_ (list))))]
                        (fold (fn [(acc (List RollbackEntry)) (ef rd/SExpr)] -> (List RollbackEntry)
                                (mt (parseRollbackEntryNode ef)
                                  ((some re) (list-append acc (list re)))
                                  ((none) acc)))
                              (list)
                              entryForms))))))
                (_ (list))))))))))

(df renderRollbackEntry [(e RollbackEntry)] -> Str
  :d "Renders a single RollbackEntry record to ASN format."
  (let [(invText (patch/renderPatch (.-inversePatch e)))]
    (str "    (:rollbackEntry\n"
         "      :patchId \"" (.-patchId e) "\"\n"
         "      :targetFile \"" (.-targetFile e) "\"\n"
         "      :targetModule \"" (.-targetModule e) "\"\n"
         "      :preRoot \"" (.-preRoot e) "\"\n"
         "      :postRoot \"" (.-postRoot e) "\"\n"
         "      :timestamp " (string-from-int64 (.-timestamp e)) "\n"
         "      :inversePatch " invText ")\n")))

(df renderPatchStackFile [(entries (List RollbackEntry))] -> Str
  :d "Renders a list of RollbackEntry records into canonical .asl/mem/patch_stack.asn format."
  (let [(renderedEntries (map (fn [(e RollbackEntry)] -> Str (renderRollbackEntry e)) entries))]
    (str "(:patch-stack\n"
         "  :version 1\n"
         "  :entries [\n"
         (string-join renderedEntries "\n")
         "  ])\n")))

(df pushRollbackStack [(entry RollbackEntry)] -> (Result Unit Str)
  :d "Pushes an inverse patch entry onto the external LIFO rollback stack."
  (let [(path ".asl/mem/patch_stack.asn")
        (readRes (file-read path))
        (content (mt readRes ((ok s) s) ((err _) "")))]
    (let [(entries (parsePatchStackFile content))
          (updated (list-cons entry entries))
          (rendered (renderPatchStackFile updated))
          (writeRes (file-write path rendered))]
      (mt writeRes
        ((ok _) (ok ()))
        ((err e) (err (str "Failed to write rollback stack: " path)))))))

(df takeEntries [(n Int64) (xs (List RollbackEntry))] -> (List RollbackEntry)
  :d "Takes first n rollback entries."
  (if (<= n 0)
      (list)
      (mt (list-head xs)
        ((some h)
         (list-cons h (takeEntries (- n 1) (option-or (list-tail xs) (list)))))
        ((none) (list)))))

(df dropEntries [(n Int64) (xs (List RollbackEntry))] -> (List RollbackEntry)
  :d "Drops first n rollback entries."
  (if (<= n 0)
      xs
      (mt (list-tail xs)
        ((some tl) (dropEntries (- n 1) tl))
        ((none) (list)))))

(df popRollbackStack [(count Int64)] -> (Result (List RollbackEntry) Str)
  :d "Pops count entries from the LIFO rollback stack with dirty-state verification."
  (let [(path ".asl/mem/patch_stack.asn")
        (readRes (file-read path))]
    (mt readRes
      ((err _) (err "Rollback stack file '.asl/mem/patch_stack.asn' not found"))
      ((ok content)
       (let [(entries (parsePatchStackFile content))]
         (if (list-empty? entries)
             (err "Rollback stack is empty; zero patches to rollback")
             (let [(effectiveCount (if (<= count 0) 1 count))
                   (toPop (takeEntries effectiveCount entries))
                   (remaining (dropEntries effectiveCount entries))
                   (dirtyCheck (fold (fn [(acc (Option Str)) (entry RollbackEntry)] -> (Option Str)
                                       (mt acc
                                         ((some errStr) (some errStr))
                                         ((none)
                                          (let [(tFile (.-targetFile entry))
                                                (fRead (file-read tFile))]
                                            (mt fRead
                                              ((err _) (some (str "Target file '" tFile "' not found on disk")))
                                              ((ok fContent)
                                               (let [(actualDigest (patch/computeAstDigest fContent))]
                                                 (if (!= actualDigest (.-postRoot entry))
                                                     (some (str "(:err :dirtyRollbackState :target \"" tFile "\" :expected \"" (.-postRoot entry) "\" :actual \"" actualDigest "\" :message \"Refusing rollback: external file drift detected\")"))
                                                     (none)))))))))
                                     (none)
                                     toPop))]
               (mt dirtyCheck
                 ((some errReceipt)
                  (err errReceipt))
                 ((none)
                  (let [(applyStep (fold (fn [(acc (Result Unit Str)) (entry RollbackEntry)] -> (Result Unit Str)
                                           (mt acc
                                             ((err e) (err e))
                                             ((ok _)
                                              (let [(tFile (.-targetFile entry))
                                                    (content (option-or (mt (file-read tFile) ((ok s) (some s)) ((err _) (none))) ""))
                                                    (res (patch/applyPatch (.-inversePatch entry) content))]
                                                (if (not (.-success res))
                                                    (err (str "Failed to apply inverse patch for " (.-patchId entry)))
                                                    (let [(wRes (file-write tFile (.-patchedSource res)))]
                                                      (mt wRes
                                                        ((ok _) (ok ()))
                                                        ((err _) (err (str "Failed to persist rolled back file: " tFile))))))))))
                                         (ok ())
                                         toPop))]
                    (mt applyStep
                      ((err e) (err e))
                      ((ok _)
                       (let [(renderedRem (renderPatchStackFile remaining))
                             (writeRes (file-write path renderedRem))]
                         (mt writeRes
                           ((ok _) (ok toPop))
                           ((err _) (err "Failed to update patch stack after rollback"))))))))))))))))

(df resolveTargetFile [(patchTargetModule Str) (explicitFile (Option Str))] -> Str
  :d "Resolves target file path from explicit argument or targetModule."
  (mt explicitFile
    ((some f) f)
    ((none)
     (let [(cleanMod (string-replace patchTargetModule ".asl" ""))]
       (str cleanMod ".asl")))))

(df executePatchCheck [(patchPath Str) (targetFilePath (Option Str))] -> (Result Str Str)
  :d "Validates AST patch pre-conditions and dry-run application without mutating disk."
  (let [(patchRead (file-read patchPath))]
    (mt patchRead
      ((err _) (err (str "Patch file not found: " patchPath)))
      ((ok patchText)
       (let [(parsedRes (patch/parsePatch patchText))]
         (mt parsedRes
           ((err d)
            (err (str "(:patch-receipt :action :check :status :rejected :diagnostics [(:diag :code \"" (.-code d) "\" :target \"" (.-target d) "\" :anchor \"" (.-anchor d) "\" :message \"" (.-message d) "\")])")))
           ((ok p)
            (let [(tPath (resolveTargetFile (.-targetModule p) targetFilePath))
                  (srcRead (file-read tPath))]
              (mt srcRead
                ((err _) (err (str "Target file not found for check: " tPath)))
                ((ok srcText)
                 (let [(vfyRes (patch/verifyPatch p srcText))]
                   (mt vfyRes
                     ((ok _)
                      (ok (str "(:patch-receipt :action :check :patchId \"" (.-id p) "\" :targetModule \"" (.-targetModule p) "\" :targetFile \"" tPath "\" :status :ok)")))
                     ((err diags)
                      (let [(diagLines (map (fn [(d patch/PatchDiag)] -> Str
                                              (str "(:diag :code \"" (.-code d) "\" :target \"" (.-target d) "\" :anchor \"" (.-anchor d) "\" :message \"" (.-message d) "\")"))
                                            diags))]
                        (err (str "(:patch-receipt :action :check :patchId \"" (.-id p) "\" :targetModule \"" (.-targetModule p) "\" :status :rejected :diagnostics [" (string-join diagLines " ") "])"))))))))))))))))

(df executePatchApply [(patchPath Str) (targetFilePath (Option Str))] -> (Result Str Str)
  :d "Applies an AST patch, verifies Merkle pre-conditions, and pushes to rollback stack."
  (let [(patchRead (file-read patchPath))]
    (mt patchRead
      ((err _) (err (str "Patch file not found: " patchPath)))
      ((ok patchText)
       (let [(parsedRes (patch/parsePatch patchText))]
         (mt parsedRes
           ((err d)
            (err (str "(:patch-receipt :action :apply :status :rejected :diagnostics [(:diag :code \"" (.-code d) "\" :target \"" (.-target d) "\" :anchor \"" (.-anchor d) "\" :message \"" (.-message d) "\")])")))
           ((ok p)
            (let [(tPath (resolveTargetFile (.-targetModule p) targetFilePath))
                  (srcRead (file-read tPath))]
              (mt srcRead
                ((err _) (err (str "Target file not found for apply: " tPath)))
                ((ok srcText)
                 (let [(preRoot (patch/computeAstDigest srcText))]
                   (mt (.-preRoot p)
                     ((some expected)
                      (if (not (validateMerkleRoot expected preRoot))
                          (err (str "(:err :concurrencyConflict :expected \"" expected "\" :actual \"" preRoot "\" :divergedAnchors [" (string-join (map (fn [(op patch/AstPatchOp)] -> Str (str "\"" (getOpAnchorKey op) "\"")) (.-ops p)) " ") "])"))
                          (let [(res (patch/applyPatch p srcText))]
                            (if (not (.-success res))
                                (let [(diagLines (map (fn [(d patch/PatchDiag)] -> Str
                                                        (str "(:diag :code \"" (.-code d) "\" :target \"" (.-target d) "\" :anchor \"" (.-anchor d) "\" :message \"" (.-message d) "\")"))
                                                      (.-diagnostics res)))]
                                  (err (str "(:patch-receipt :action :apply :patchId \"" (.-id p) "\" :status :failed :diagnostics [" (string-join diagLines " ") "])")))
                                (let [(wRes (file-write tPath (.-patchedSource res)))]
                                  (mt wRes
                                    ((err _) (err (str "Failed to write patched file: " tPath)))
                                    ((ok _)
                                     (let [(postRoot (patch/computeAstDigest (.-patchedSource res)))
                                           (inv (option-or (.-inversePatch res) p))
                                           (entry (makeRollbackEntry (.-id p) tPath (.-targetModule p) preRoot postRoot inv 1789720000000))
                                           (pushed (pushRollbackStack entry))]
                                       (ok (str "(:patch-receipt :action :apply :patchId \"" (.-id p) "\" :targetModule \"" (.-targetModule p) "\" :targetFile \"" tPath "\" :preRoot \"" preRoot "\" :postRoot \"" postRoot "\" :status :ok)"))))))))))
                     ((none)
                      (let [(res (patch/applyPatch p srcText))]
                        (if (not (.-success res))
                            (let [(diagLines (map (fn [(d patch/PatchDiag)] -> Str
                                                    (str "(:diag :code \"" (.-code d) "\" :target \"" (.-target d) "\" :anchor \"" (.-anchor d) "\" :message \"" (.-message d) "\")"))
                                                  (.-diagnostics res)))]
                              (err (str "(:patch-receipt :action :apply :patchId \"" (.-id p) "\" :status :failed :diagnostics [" (string-join diagLines " ") "])")))
                            (let [(wRes (file-write tPath (.-patchedSource res)))]
                              (mt wRes
                                ((err _) (err (str "Failed to write patched file: " tPath)))
                                ((ok _)
                                 (let [(postRoot (patch/computeAstDigest (.-patchedSource res)))
                                       (inv (option-or (.-inversePatch res) p))
                                       (entry (makeRollbackEntry (.-id p) tPath (.-targetModule p) preRoot postRoot inv 1789720000000))
                                       (pushed (pushRollbackStack entry))]
                                   (ok (str "(:patch-receipt :action :apply :patchId \"" (.-id p) "\" :targetModule \"" (.-targetModule p) "\" :targetFile \"" tPath "\" :preRoot \"" preRoot "\" :postRoot \"" postRoot "\" :status :ok)")))))))))))))))))))))

(df executePatchRollback [(countOpt (Option Int64))] -> (Result Str Str)
  :d "Rolls back previous patch modifications by popping the LIFO rollback stack."
  (let [(cnt (option-or countOpt 1))
        (popRes (popRollbackStack cnt))]
    (mt popRes
      ((err e) (err e))
      ((ok popped)
       (let [(ids (map (fn [(e RollbackEntry)] -> Str (str "\"" (.-patchId e) "\"")) popped))]
         (ok (str "(:patch-receipt :action :rollback :count " (string-from-int64 (list-length popped)) " :revertedPatches [" (string-join ids " ") "] :status :ok)")))))))

(df formatPatchHelp [] -> Str
  :d "Returns usage manual for asl patch subcommand."
  (str "Usage: asl patch [options]\n\n"
       "Options:\n"
       "  --apply <patch-file> [target-file]  Apply AST patch with Merkle pre-condition checks\n"
       "  --check <patch-file> [target-file]  Dry-run AST patch validity without disk writes\n"
       "  --rollback [count]                  Pop inverse patches from LIFO rollback journal\n\n"
       "[Teleology] Principle: GroundTruthOverReport (ADR D94)\n"
       "  \"Agent code modifications must execute as verified AST delta streams without line numbers.\"\n\n"
       "[Assistive Ontology] Enforces Optimistic Concurrency & Rollback Invariants:\n"
       "  • Merkle Pre-condition Verification: Detects concurrent divergence prior to AST mutation\n"
       "  • Dirty-State Rollback Defense: Aborts rollback if target file was modified externally\n"
       "  • Zero-Line-Number Invariant: Code addressed strictly by Module:symbol and :anchor\n"))

(df runPatchCommand [(args (List Str))] -> (Result Str Str)
  :d "Top-level command dispatcher for asl patch subcommand."
  (if (list-empty? args)
      (ok (formatPatchHelp))
      (let [(flag (option-or (list-head args) ""))
            (restArgs (option-or (list-tail args) (list)))]
        (cond
          ((or (= flag "--help") (= flag "-h") (= flag "help"))
           (ok (formatPatchHelp)))
          ((= flag "--check")
           (if (list-empty? restArgs)
               (err "Usage: asl patch --check <patch-file> [target-file]")
               (let [(pPath (option-or (list-head restArgs) ""))
                     (tOpt (list-head (option-or (list-tail restArgs) (list))))]
                 (executePatchCheck pPath tOpt))))
          ((= flag "--apply")
           (if (list-empty? restArgs)
               (err "Usage: asl patch --apply <patch-file> [target-file]")
               (let [(pPath (option-or (list-head restArgs) ""))
                     (tOpt (list-head (option-or (list-tail restArgs) (list))))]
                 (executePatchApply pPath tOpt))))
          ((= flag "--rollback")
           (let [(cntStr (option-or (list-head restArgs) "1"))
                 (cnt (option-or (string-to-int64 cntStr) 1))]
             (executePatchRollback (some cnt))))
          (:else
           (err (str "Unknown flag '" flag "'. Usage: asl patch [--apply|--check|--rollback] <file>")))))))
