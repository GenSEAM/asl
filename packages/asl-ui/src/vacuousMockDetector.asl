(module asl-ui/vacuousMockDetector :x [BadgeState VacuousMockAnomaly VacuousMockItem makeVacuousMockItem badgeVerified badgeFailed badgeIncomplete badgeStale badgeInconclusive badgeRunning anomalyHollowMock anomalyZeroAssertions anomalyTautologicalAssert anomalyCleanConstant classifyMockAnomaly anomalyToString badgeStateToString formatBadgeIndicator renderVacuousMockTile] :i [(asl-ui/vnode :a ui) (asl-ui/theme :a theme)])

(enum BadgeState (:c badgeVerified [] "Certified verified with non-vacuous assertions and killed mutants") (:c badgeFailed [] "Failed assertion or surviving mutant") (:c badgeIncomplete [] "Incomplete verification or unexercised branches") (:c badgeStale [] "Stale verification receipt from prior commit snapshot") (:c badgeInconclusive [] "Inconclusive execution due to timeout or infrastructure crash") (:c badgeRunning [] "Active gate verification currently running"))

(enum VacuousMockAnomaly (:c anomalyHollowMock [] "Hollow test double with zero production reachability") (:c anomalyZeroAssertions [] "Vacuous test passing with assertCount == 0") (:c anomalyTautologicalAssert [] "Tautological assertion without refutable predicate") (:c anomalyCleanConstant [] "Legitimate pure constant or identity function"))

(schema VacuousMockItem (:f targetSymbol String) (:f filePath String) (:f cyclomaticComplexity Int64) (:f assertCount Int64) (:f anomaly VacuousMockAnomaly) (:f isVerifiedProductionReachable Bool))

fn makeVacuousMockItem sym: String file: String complexity: Int64 asserts: Int64 anomaly: VacuousMockAnomaly reachable: Bool -> VacuousMockItem
  (VacuousMockItem :targetSymbol sym :filePath file :cyclomaticComplexity complexity :assertCount asserts :anomaly anomaly :isVerifiedProductionReachable reachable)

fn classifyMockAnomaly complexity: Int64 asserts: Int64 reachable: Bool -> VacuousMockAnomaly
  (if (and (= complexity 0) (not reachable)) (anomalyHollowMock) (if (= asserts 0) (anomalyZeroAssertions) (if (and (= complexity 0) reachable) (anomalyCleanConstant) (anomalyCleanConstant))))

fn anomalyToString anomaly: VacuousMockAnomaly -> String
  (mt anomaly ((anomalyHollowMock) "hollowMock") ((anomalyZeroAssertions) "zeroAssertions") ((anomalyTautologicalAssert) "tautologicalAssert") ((anomalyCleanConstant) "cleanConstant"))

fn badgeStateToString state: BadgeState -> String
  (mt state ((badgeVerified) "verified") ((badgeFailed) "failed") ((badgeIncomplete) "incomplete") ((badgeStale) "stale") ((badgeInconclusive) "inconclusive") ((badgeRunning) "running"))

fn formatBadgeIndicator state: BadgeState -> String
  (mt state ((badgeVerified) "[OK] Verified") ((badgeFailed) "[FAIL] Failed") ((badgeIncomplete) "[VACUOUS] Incomplete") ((badgeStale) "[STALE] Stale Snapshot") ((badgeInconclusive) "[WARN] Inconclusive") ((badgeRunning) "[RUN] Executing"))

fn renderMockItemCard item: VacuousMockItem -> ui/VNode
  (let [(cue (mt item.anomaly ((anomalyHollowMock) "[VACUOUS] Hollow Mock") ((anomalyZeroAssertions) "[VACUOUS] 0 Assertions") ((anomalyTautologicalAssert) "[WARN] Tautological") ((anomalyCleanConstant) "[OK] Clean Constant"))) (titleText (str item.targetSymbol " (" cue ")")) (metaText (str "File: " item.filePath " | Asserts: " (stringFromInt64 item.assertCount))) (attrs (mapSet (mapSet (mapEmpty) "class" "sds1-mock-item") "data-symbol" item.targetSymbol))] (ui/makeContainer (str "mock-" item.targetSymbol) attrs (list (ui/makeText titleText "mock-title") (ui/makeText metaText "mock-meta"))))

fn renderVacuousMockTile items: (List VacuousMockItem) -> ui/VNode
  (let [(count (listLength items)) (headerText (str "Vacuous Verification & Hollow Mock Detector (" (stringFromInt64 count) " findings)")) (headerNode (ui/makeText headerText "detector-title")) (cards (fold (fn [(acc (List ui/VNode)) (it VacuousMockItem)] -> (List ui/VNode) (listAppend acc (list (renderMockItemCard it)))) (list) items)) (tileAttrs (mapSet (mapSet (mapEmpty) "class" "sds1-vacuous-mock-card") "data-count" (stringFromInt64 count)))] (ui/makeContainer "vacuous-mock-root" tileAttrs (cons headerNode cards)))
