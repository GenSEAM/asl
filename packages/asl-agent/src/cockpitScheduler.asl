(module aslAgent/cockpitScheduler :x [CockpitViewState makeCockpitViewState CockpitJobState makeCockpitJobState switchFocusedPane verifyFocusInvariant routeExecutionReceipt resolveWorkspaceVisibility isReceiptStale?] :i [(asl-text/string :a s)])

(schema CockpitViewState (:f focusedPaneId String) (:f visibleWorkspaceId String) (:f activeViewRevision Int64))

(schema CockpitJobState (:f jobId String) (:f originWorkspaceId String) (:f ownsPath String) (:f leaseId String) (:f leaseEpoch Int64) (:f isCancelled Bool))

fn makeCockpitViewState pane: String ws: String rev: Int64 -> CockpitViewState
  (CockpitViewState :focusedPaneId pane :visibleWorkspaceId ws :activeViewRevision rev)

fn makeCockpitJobState id: String originWs: String owns: String lease: String epoch: Int64 -> CockpitJobState
  (CockpitJobState :jobId id :originWorkspaceId originWs :ownsPath owns :leaseId lease :leaseEpoch epoch :isCancelled false)

fn switchFocusedPane view: CockpitViewState newPaneId: String newWorkspaceId: String -> CockpitViewState
  (CockpitViewState :focusedPaneId newPaneId :visibleWorkspaceId newWorkspaceId :activeViewRevision (+ view.activeViewRevision 1))

fn verifyFocusInvariant jobBefore: CockpitJobState jobAfter: CockpitJobState -> Bool
  (and (and (= jobBefore.originWorkspaceId jobAfter.originWorkspaceId) (= jobBefore.ownsPath jobAfter.ownsPath)) (= jobBefore.leaseEpoch jobAfter.leaseEpoch))

fn isReceiptStale? job: CockpitJobState receiptEpoch: Int64 -> Bool
  (< receiptEpoch job.leaseEpoch)

fn routeExecutionReceipt job: CockpitJobState receiptJobId: String receiptWsId: String receiptEpoch: Int64 -> (Result Bool String)
  (if (not (= job.jobId receiptJobId)) (err "ERR_JOB_ID_MISMATCH") (if (not (= job.originWorkspaceId receiptWsId)) (err "ERR_CROSS_WORKSPACE_CONTAMINATION") (if (isReceiptStale? job receiptEpoch) (err "ERR_STALE_LEASE_EPOCH") (ok true))))

fn resolveWorkspaceVisibility tier: String isAtGlobalAslAnchor: Bool -> (Result String String)
  (if (= tier "session") (ok "tier-session") (if (= tier "workspace") (ok "tier-workspace-lineage") (if (= tier "panopticon") (if isAtGlobalAslAnchor (ok "tier-panopticon") (err "ERR_PANOPTICON_UNAUTHORIZED")) (err "ERR_UNKNOWN_VISIBILITY_TIER"))))
