(module aslMem/visibilityScope :x [VisibilityTier VisibilityContext makeVisibilityContext isGlobalAslAnchor? resolveVisibilityTier filterVisibleWorktrees filterVisibleSessions filterVisibleRepos] :i [])

(enum VisibilityTier (:c tierIsolatedSession [] "Unanchored session: only current session visible") (:c tierWorkspaceLineage [] "Workspace-anchored: workspace and derived child worktrees") (:c tierSovereignSystem [] "Global .asl anchor: panoptic whole-system visibility"))

(schema VisibilityContext (:f currentCwd Str) (:f activeSessionId Str) (:f globalAslDir Str) (:f tier VisibilityTier) (:f activeWorkspaceRoot Str) (:f visibleWorktrees (List Str)) (:f visibleRepos (List Str)) (:f visibleSessionIds (List Str)))

fn isGlobalAslAnchor? cwd: Str globalAslDir: Str -> Bool
  (let [(normCwd (if (stringEndsWith? cwd "/") (optionOr (stringSlice cwd 0 (- (stringLength cwd) 1)) "") cwd)) (normGlobal (if (stringEndsWith? globalAslDir "/") (optionOr (stringSlice globalAslDir 0 (- (stringLength globalAslDir) 1)) "") globalAslDir)) (expected (str normCwd "/.asl"))] (= expected normGlobal))

fn resolveVisibilityTier cwd: Str isInWorkspace: Bool isGlobalAnchor: Bool -> VisibilityTier
  (if isGlobalAnchor (tierSovereignSystem) (if isInWorkspace (tierWorkspaceLineage) (tierIsolatedSession)))

fn filterVisibleWorktrees tier: VisibilityTier currentWs: Str childWts: (List Str) allWts: (List Str) -> (List Str)
  (mt tier ((tierIsolatedSession) (list)) ((tierWorkspaceLineage) (cons currentWs childWts)) ((tierSovereignSystem) allWts))

fn filterVisibleSessions tier: VisibilityTier activeSess: Str wsSessions: (List Str) allSessions: (List Str) -> (List Str)
  (mt tier ((tierIsolatedSession) (list activeSess)) ((tierWorkspaceLineage) (cons activeSess wsSessions)) ((tierSovereignSystem) allSessions))

fn filterVisibleRepos tier: VisibilityTier currentRepo: Str allRepos: (List Str) -> (List Str)
  (mt tier ((tierIsolatedSession) (list)) ((tierWorkspaceLineage) (list currentRepo)) ((tierSovereignSystem) allRepos))

fn makeVisibilityContext cwd: Str activeSess: Str globalAslDir: Str isInWs: Bool currentWs: Str currentRepo: Str childWts: (List Str) allWts: (List Str) wsSessions: (List Str) allSessions: (List Str) allRepos: (List Str) -> VisibilityContext
  (let [(isAnchor (isGlobalAslAnchor? cwd globalAslDir)) (tier (resolveVisibilityTier cwd isInWs isAnchor)) (visWts (filterVisibleWorktrees tier currentWs childWts allWts)) (visSess (filterVisibleSessions tier activeSess wsSessions allSessions)) (visRepos (filterVisibleRepos tier currentRepo allRepos))] (VisibilityContext :currentCwd cwd :activeSessionId activeSess :globalAslDir globalAslDir :tier tier :activeWorkspaceRoot (mt tier ((tierWorkspaceLineage) currentWs) (_ "")) :visibleWorktrees visWts :visibleRepos visRepos :visibleSessionIds visSess))
