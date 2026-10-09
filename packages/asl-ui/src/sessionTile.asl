(module asl-ui/sessionTile :x [SessionStatus SessionCardItem makeSessionCardItem statusActive statusIdle statusRunning statusBlocked formatSessionCue renderSessionCard renderSessionTile calculateSessionTileHash] :i [(asl-ui/vnode :a ui) (asl-ui/theme :a theme)])

(enum SessionStatus (:c statusActive [] "Session is active and responding") (:c statusIdle [] "Session is in standby/idle") (:c statusRunning [] "Session is executing background task") (:c statusBlocked [] "Session is waiting on operator confirmation"))

(schema SessionCardItem (:f targetId String) (:f substrateName String) (:f activeTabsCount Int64) (:f isAuthenticated Bool) (:f status SessionStatus) (:f currentTask String))

fn makeSessionCardItem id: String sub: String tabs: Int64 auth: Bool status: SessionStatus task: String -> SessionCardItem
  (SessionCardItem :targetId id :substrateName sub :activeTabsCount tabs :isAuthenticated auth :status status :currentTask task)

fn formatSessionCue status: SessionStatus -> String
  (mt status ((statusActive) "[OK] Active") ((statusRunning) "[RUN] Executing") ((statusIdle) "[IDLE] Standby") ((statusBlocked) "[BLOCKED] Safety Hold"))

fn renderSessionCard item: SessionCardItem -> ui/VNode
  (let [(cue (formatSessionCue item.status)) (authStr (if item.isAuthenticated "Authenticated SaaS" "Isolated Sandbox")) (titleText (str item.substrateName " (" cue ")")) (metaText (str "Target: " item.targetId " | Tabs: " (stringFromInt64 item.activeTabsCount) " | " authStr " | Task: " item.currentTask)) (attrs (mapSet (mapSet (mapEmpty) "class" "sds1-session-card") "data-target" item.targetId))] (ui/makeContainer (str "sess-" item.targetId) attrs (list (ui/makeText titleText "session-title") (ui/makeText metaText "session-meta"))))

fn renderSessionTile items: (List SessionCardItem) -> ui/VNode
  (let [(count (listLength items)) (headerText (str "Browser & Host Agent Sessions (" (stringFromInt64 count) " active targets)")) (headerNode (ui/makeText headerText "session-tile-title")) (cards (fold (fn [(acc (List ui/VNode)) (it SessionCardItem)] -> (List ui/VNode) (listAppend acc (list (renderSessionCard it)))) (list) items)) (tileAttrs (mapSet (mapSet (mapEmpty) "class" "sds1-session-bento-tile") "data-count" (stringFromInt64 count)))] (ui/makeContainer "session-tile-root" tileAttrs (cons headerNode cards)))

fn calculateSessionTileHash items: (List SessionCardItem) -> Int64
  (fold (fn [(acc Int64) (it SessionCardItem)] -> Int64 (+ (+ acc (stringLength it.targetId)) it.activeTabsCount)) 0 items)
