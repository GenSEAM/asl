(module aslHarness/selfOrgToolkit :x [TodoItem TodoLedger NoteEntry WorkingMemory SnapshotMarker ProbeReceipt LensReport TerminationProof makeEmptyLedger addTodoItem markTodoDone markTodoBlocked makeWorkingMemory recordNote lookupNote createSnapshot restoreSnapshot evaluateProbe evaluateLenses validateTerminationProof formatToolkitReceipt] :i [])

(schema TodoItem (:f id Str) (:f description Str) (:f intentAtom Str) (:f completed Bool) (:f verifyingProbe Str) (:f blockedReason Str) (:f failureCount I64))

(schema TodoLedger (:f items (List TodoItem)) (:f pendingCount I64) (:f completedCount I64) (:f trippedLimitCycle Bool))

(schema NoteEntry (:f key Str) (:f value Str) (:f source Str) (:f timestamp I64))

(schema WorkingMemory (:f notes (List NoteEntry)) (:f entryCount I64))

(schema SnapshotMarker (:f id Str) (:f scope Str) (:f preHash Str) (:f timestamp I64) (:f active Bool))

(schema ProbeReceipt (:f probeName Str) (:f intentAtom Str) (:f passed Bool) (:f exitCode I64) (:f assertCount I64) (:f durationMs I64) (:f invertPassed Bool) (:f baselineFailed Bool))

(schema LensReport (:f intentPassed Bool) (:f boundariesPassed Bool) (:f diffClean Bool) (:f healthScore F64) (:f limitCycleCount I64) (:f thresholdsPassed Bool))

(schema TerminationProof (:f taskClosed Bool) (:f proofDescription Str) (:f probesVerified Bool) (:f todosResolved Bool) (:f intentBound Bool))

fn makeEmptyLedger -> TodoLedger
  (TodoLedger :items (list) :pendingCount 0 :completedCount 0 :trippedLimitCycle false)

fn addTodoItem ledger: TodoLedger id: Str desc: Str intent: Str -> TodoLedger
  (let [(newItem (TodoItem :id id :description desc :intentAtom intent :completed false :verifyingProbe "" :blockedReason "" :failureCount 0)) (current ledger.items) (updated (listAppend current (list newItem))) (pCount (+ ledger.pendingCount 1))] (with ledger :items updated :pendingCount pCount))

fn markTodoDone ledger: TodoLedger id: Str probeId: Str -> TodoLedger
  (if (<= (stringLength probeId) 0) ledger (let [(current ledger.items) (updated (map (fn [(it TodoItem)] -> TodoItem (if (= it.id id) (TodoItem :id it.id :description it.description :intentAtom it.intentAtom :completed true :verifyingProbe probeId :blockedReason "" :failureCount 0) it)) current)) (doneCount (+ ledger.completedCount 1)) (pCount (if (> ledger.pendingCount 0) (- ledger.pendingCount 1) 0))] (with ledger :items updated :pendingCount pCount :completedCount doneCount)))

fn markTodoBlocked ledger: TodoLedger id: Str reason: Str -> TodoLedger
  (let [(current ledger.items) (updated (map (fn [(it TodoItem)] -> TodoItem (if (= it.id id) (let [(newFail (+ it.failureCount 1))] (TodoItem :id it.id :description it.description :intentAtom it.intentAtom :completed false :verifyingProbe "" :blockedReason reason :failureCount newFail)) it)) current)) (hasTripped (fold (fn [(acc Bool) (it TodoItem)] -> Bool (or acc (>= it.failureCount 3))) false updated))] (with ledger :items updated :trippedLimitCycle hasTripped))

fn makeWorkingMemory -> WorkingMemory
  (WorkingMemory :notes (list) :entryCount 0)

fn recordNote mem: WorkingMemory key: Str val: Str src: Str now: I64 -> WorkingMemory
  (let [(current mem.notes) (filtered (filter (fn [(n NoteEntry)] -> Bool (!= n.key key)) current)) (newEntry (NoteEntry :key key :value val :source src :timestamp now)) (updated (listAppend filtered (list newEntry))) (c (+ (listLength filtered) 1))] (WorkingMemory :notes updated :entryCount c))

fn lookupNote mem: WorkingMemory key: Str -> Str
  (let [(matches (filter (fn [(n NoteEntry)] -> Bool (= n.key key)) mem.notes))] (mt (listHead matches) ((some n) n.value) ((none) "")))

fn createSnapshot id: Str scope: Str hash: Str now: I64 -> SnapshotMarker
  (SnapshotMarker :id id :scope scope :preHash hash :timestamp now :active true)

fn restoreSnapshot snap: SnapshotMarker targetHash: Str -> (Pair SnapshotMarker Bool)
  (if (and snap.active (= snap.preHash targetHash)) (pair snap true) (pair snap false))

fn evaluateProbe name: Str intent: Str exitCode: I64 assertCount: I64 durationMs: I64 invertPassed: Bool baselineFailed: Bool -> ProbeReceipt
  (let [(isPass (and (= exitCode 0) (and (> assertCount 0) (and invertPassed baselineFailed))))] (ProbeReceipt :probeName name :intentAtom intent :passed isPass :exitCode exitCode :assertCount assertCount :durationMs durationMs :invertPassed invertPassed :baselineFailed baselineFailed))

fn evaluateLenses intent: Bool boundaries: Bool diffClean: Bool errCount: I64 maxErr: I64 -> LensReport
  (let [(score (if (and intent (and boundaries diffClean)) 1.0 0.0)) (clampedErr (if (< errCount 0) 0 errCount)) (tPassed (and (= score 1.0) (< clampedErr maxErr)))] (LensReport :intentPassed intent :boundariesPassed boundaries :diffClean diffClean :healthScore score :limitCycleCount clampedErr :thresholdsPassed tPassed))

fn validateTerminationProof proofDesc: Str probesOk: Bool externalSuiteOk: Bool intentBound: Bool ledger: TodoLedger -> TerminationProof
  (let [(hasEvidence (or probesOk externalSuiteOk)) (zeroPending (= ledger.pendingCount 0)) (noTrip (not ledger.trippedLimitCycle)) (hasDesc (> (stringLength proofDesc) 0)) (allProbesSet (fold (fn [(acc Bool) (it TodoItem)] -> Bool (and acc (> (stringLength it.verifyingProbe) 0))) true ledger.items)) (canClose (and hasEvidence (and zeroPending (and intentBound (and noTrip (and hasDesc allProbesSet))))))] (TerminationProof :taskClosed canClose :proofDescription proofDesc :probesVerified probesOk :todosResolved zeroPending :intentBound intentBound))

fn formatToolkitReceipt ledger: TodoLedger mem: WorkingMemory probe: ProbeReceipt -> Str
  (let [(probeStatus (if probe.passed ":pass" ":fail"))] (str "(:toolkit-receipt :completed-todos " (stringFromInt64 ledger.completedCount) " :pending-todos " (stringFromInt64 ledger.pendingCount) " :cached-notes " (stringFromInt64 mem.entryCount) " :last-probe-status " probeStatus " :assert-count " (stringFromInt64 probe.assertCount) ")"))
