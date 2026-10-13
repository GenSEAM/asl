(module asl-engine/supervisor
  :x [SessionRecord SupervisorState makeSupervisorState
      findSession removeSession
      spawnSession! spawnSessionWith! spawnEnv pollSession! tailSession! killSession! sendSession! listSessionsReceipt
      reapSessions! runningCount killAllSessions! finishedLines loadFinished]
  :i [(asl-engine/wire :a w)])

(schema SessionRecord
  (:f id String)
  (:f pid Int64)
  (:f cmd String)
  (:f cwd String)
  (:f startTimeSec Int64)
  (:f state String)
  (:f exitCode Int64)
  (:f durationMs Int64)
  (:f logPath String)
  (:f stdinFd Int64)
  (:f stdinOpen Bool))

(schema SupervisorState
  (:f sessions (List SessionRecord))
  (:f finished (List SessionRecord)))

fn makeSupervisorState -> SupervisorState
  (SupervisorState :sessions (list) :finished (list))
fn findSessionLoop sessions: (List SessionRecord) id: String -> (Option SessionRecord)
  (mt (listHead sessions)
    ((none)
      (none))
    ((some s)
      (if (= s.id id)
        (some s)
        (findSessionLoop (optionOr (listTail sessions) (list)) id))))
fn findSession state: SupervisorState id: String -> (Option SessionRecord)
  (mt (findSessionLoop state.sessions id)
    ((some s)
      (some s))
    ((none)
      (findSessionLoop state.finished id)))
fn removeSessionLoop sessions: (List SessionRecord) id: String acc: (List SessionRecord) -> (List SessionRecord)
  (mt (listHead sessions)
    ((none)
      (listReverse acc))
    ((some s)
      (if (= s.id id)
        (removeSessionLoop (optionOr (listTail sessions) (list)) id acc)
        (removeSessionLoop (optionOr (listTail sessions) (list)) id (cons s acc)))))
fn removeSession sessions: (List SessionRecord) id: String -> (List SessionRecord)
  (removeSessionLoop sessions id (list))
fn envKey row: String -> String
  (mt (stringIndexOf row "=") ((some i) (optionOr (stringSlice row 0 i) row)) ((none) row))

fn spawnEnv rows: (List String) absCwd: String unset: String setenv: String -> (List String)
  (let [(hidden (filter (fn [(k String)] -> Bool (not (stringEmpty? k))) (stringSplit (stringReplace unset "\t" " ") " ")))
        (pairs (filter (fn [(kv String)] -> Bool (some? (stringIndexOf kv "="))) (stringSplit setenv " ")))
        (setKeys (map envKey pairs))
        (base (filter (fn [(r String)] -> Bool (let [(k (envKey r))] (not (or (= k "PWD") (listContains? hidden k) (listContains? setKeys k))))) rows))]
    (listAppend (listAppend base (list (str "PWD=" absCwd))) pairs))

fn spawnSession! state: SupervisorState id: String cmd: String cwd: String stdin: Bool nowSec: Int64 -> (Pair SupervisorState String)
  (spawnSessionWith! state id cmd cwd stdin "" "" nowSec)

fn spawnSessionWith! state: SupervisorState id: String cmd: String cwd: String stdin: Bool unset: String setenv: String nowSec: Int64 -> (Pair SupervisorState String)
  (if (not (w/validSessionId? id))
    (pair state (w/formatReceiptInvalidId id))
    (if (or (stringEmpty? id) (stringEmpty? cmd))
      (pair state (w/formatReceiptError "Missing cmd or id for spawn"))
      (let [(cwdStat (fileStat cwd))]
        (if (not (mt (fileStat cwd) ((ok st) st.isDir) ((err _) false)))
          (pair state (str "(:receipt :status :error :id \"" (w/escapeStr id) "\" :message \"no directory " (w/escapeStr cwd) "\")"))
          (let [(_ (dirCreate "/tmp/asl-sessions"))
                (logPath (str "/tmp/asl-sessions/" id ".log"))
                (shCmd (str "(" cmd ") > " logPath " 2>&1"))
                (argv (list "/bin/sh" "-c" shCmd))
                (absCwd (if (stringStartsWith? cwd "/") cwd (resultOr (realPath cwd) cwd)))
                (spawnRes (procSpawnv argv (some cwd) (some (spawnEnv (envList) absCwd unset setenv))))]
            (mt spawnRes
              ((ok sp)
                (let [(pid sp.pid)
                      (inFd (if stdin sp.stdin -1))
                      (_ (if (not stdin) (fdClose sp.stdin) (ok ())))
                      (_ (fdClose sp.stdout))
                      (_ (fdClose sp.stderr))
                      (sess (SessionRecord :id id :pid pid :cmd cmd :cwd cwd :startTimeSec nowSec :state ":active" :exitCode -1 :durationMs 0 :logPath logPath :stdinFd inFd :stdinOpen stdin))
                      (newActive (cons sess (removeSession state.sessions id)))
                      (newFin (removeSession state.finished id))
                      (newState (SupervisorState :sessions newActive :finished newFin))]
                  (pair newState (w/formatSpawnActiveReceipt id pid))))
              ((err e)
                (pair state (str "(:receipt :status :error :id \"" (w/escapeStr id) "\" :message \"" (w/escapeStr e) "\")")))))))))
fn pollSession! state: SupervisorState id: String nowSec: Int64 -> (Pair SupervisorState String)
  (if (stringEmpty? id)
    (pair state (w/formatReceiptError "Missing id for poll"))
    (mt (findSessionLoop state.sessions id)
      ((some sess)
        (let [(durMs (* (max 0 (- nowSec sess.startTimeSec)) 1000))
              (pollRes (procWaitPid sess.pid true))]
          (mt pollRes
            ((ok exitOpt)
              (mt exitOpt
                ((some code)
                  (let [(stateVal (if (= code 0) ":completed" ":failed"))
                        (_ (if sess.stdinOpen (fdClose sess.stdinFd) (ok ())))
                        (finishedSess (SessionRecord :id id :pid sess.pid :cmd sess.cmd :cwd sess.cwd :startTimeSec sess.startTimeSec :state stateVal :exitCode code :durationMs durMs :logPath sess.logPath :stdinFd -1 :stdinOpen false))
                        (newState (SupervisorState :sessions (removeSession state.sessions id) :finished (cons finishedSess (removeSession state.finished id))))]
                    (pair newState (w/formatPollFinishedReceipt id stateVal code durMs))))
                ((none)
                  (let [(aliveRes (procAlive? sess.pid))]
                    (if (or (err? aliveRes) (resultOr aliveRes false))
                      (pair state (w/formatPollRunningReceipt id durMs))
                      (let [(finishedSess (SessionRecord :id id :pid sess.pid :cmd sess.cmd :cwd sess.cwd :startTimeSec sess.startTimeSec :state ":failed" :exitCode 1 :durationMs durMs :logPath sess.logPath :stdinFd -1 :stdinOpen false))
                            (newState (SupervisorState :sessions (removeSession state.sessions id) :finished (cons finishedSess (removeSession state.finished id))))]
                        (pair newState (w/formatPollFinishedReceipt id ":failed" 1 durMs))))))))
            ((err _)
              (let [(finishedSess (SessionRecord :id id :pid sess.pid :cmd sess.cmd :cwd sess.cwd :startTimeSec sess.startTimeSec :state ":failed" :exitCode 1 :durationMs durMs :logPath sess.logPath :stdinFd -1 :stdinOpen false))
                    (newState (SupervisorState :sessions (removeSession state.sessions id) :finished (cons finishedSess (removeSession state.finished id))))]
                (pair newState (w/formatPollFinishedReceipt id ":failed" 1 durMs)))))))
      ((none)
        (mt (findSessionLoop state.finished id)
          ((some fs)
            (pair state (w/formatPollFinishedReceipt id fs.state fs.exitCode fs.durationMs)))
          ((none)
            (pair state (w/formatReceiptNotFound id)))))))
fn takeLastLines lines: (List String) n: Int64 -> (List String)
  (let [(total (listLength lines))]
    (if (<= total n)
      lines
      (let [(dropCount (- total n))]
        (optionOr (listSlice lines dropCount total) (list)))))
fn tailSession! state: SupervisorState id: String linesN: Int64 -> String
  (if (or (stringEmpty? id) (not (w/validSessionId? id)))
    (if (stringEmpty? id)
      (w/formatReceiptError "Missing id for tail")
      (w/formatReceiptInvalidId id))
    (let [(logPath (str "/tmp/asl-sessions/" id ".log"))
          (statRes (fileStat logPath))]
      (if (not (ok? statRes))
        (w/formatReceiptNotFound id)
        (let [(content (resultOr (fileReadString logPath) ""))
              (lines (stringSplit content "\n"))
              (trimmedLines (if (and (> (listLength lines) 0) (stringEmpty? (optionOr (listGet lines (- (listLength lines) 1)) "x")))
                              (optionOr (listSlice lines 0 (- (listLength lines) 1)) (list))
                              lines))
              (selected (takeLastLines trimmedLines linesN))]
          (w/formatTailReceipt id selected)))))
fn killSession! state: SupervisorState id: String -> (Pair SupervisorState String)
  (if (stringEmpty? id)
    (pair state (w/formatReceiptError "Missing id for kill"))
    (mt (findSessionLoop state.sessions id)
      ((some sess)
        (let [(_ (procKill (- 0 sess.pid) "SIGTERM"))
              (_ (if sess.stdinOpen (fdClose sess.stdinFd) (ok ())))
              (_ (sleepMs 50))
              (_ (procKill (- 0 sess.pid) "SIGKILL"))
              (_ (procWaitPid sess.pid true))
              (fin (SessionRecord :id id :pid sess.pid :cmd sess.cmd :cwd sess.cwd :startTimeSec sess.startTimeSec :state ":terminated" :exitCode 137 :durationMs sess.durationMs :logPath sess.logPath :stdinFd -1 :stdinOpen false))
              (newState (SupervisorState :sessions (removeSession state.sessions id) :finished (cons fin (removeSession state.finished id))))]
          (pair newState (w/formatKillReceipt id))))
      ((none)
        (if (some? (findSessionLoop state.finished id))
          (pair state (w/formatKillReceipt id))
          (pair state (w/formatReceiptNotFound id))))))
fn sendSession! state: SupervisorState id: String text: String closeStdin: Bool -> String
  (if (stringEmpty? id)
    (w/formatReceiptError "Missing id for send")
    (mt (findSessionLoop state.sessions id)
      ((some sess)
        (if (not sess.stdinOpen)
          (str "(:receipt :status :error :id \"" (w/escapeStr id) "\" :message \"no open stdin: spawn with :stdin true, and the process must still run\")")
          (let [(payload (if (stringEndsWith? text "\n") text (str text "\n")))
                (writeRes (fdWrite sess.stdinFd payload))
                (_ (if closeStdin (fdClose sess.stdinFd) (ok ())))]
            (mt writeRes
              ((ok _)
                (w/formatSendReceipt id (stringLength text)))
              ((err e)
                (str "(:receipt :status :error :id \"" (w/escapeStr id) "\" :message \"" (w/escapeStr e) "\")"))))))
      ((none)
        (if (some? (findSessionLoop state.finished id))
          (str "(:receipt :status :error :id \"" (w/escapeStr id) "\" :message \"no open stdin: spawn with :stdin true, and the process must still run\")")
          (w/formatReceiptNotFound id)))))
fn formatSessionItem sess: SessionRecord -> String
  (str "(:session :id \"" (w/escapeStr sess.id) "\" :pid " (stringFromInt64 sess.pid) " :state " sess.state ")")
fn listSessionsReceipt state: SupervisorState -> String
  (let [(activeItems (map (fn [(s SessionRecord)] -> String (str "(:session :id \"" (w/escapeStr s.id) "\" :pid " (stringFromInt64 s.pid) " :state :running)")) state.sessions))
        (finItems (map (fn [(s SessionRecord)] -> String (formatSessionItem s)) state.finished))
        (allItems (listAppend activeItems finItems))]
    (w/formatListSessionsReceipt allItems))
fn finishSession sess: SessionRecord code: Int64 nowSec: Int64 -> SessionRecord
  (with sess :state (if (= code 0) ":completed" ":failed") :exitCode code :durationMs (* (max 0 (- nowSec sess.startTimeSec)) 1000) :stdinFd -1 :stdinOpen false)

fn ! reapSessions! state: SupervisorState nowSec: Int64 -> SupervisorState
  (fold (fn [(acc SupervisorState) (sess SessionRecord)] -> SupervisorState
          (mt (procWaitPid sess.pid true)
            ((ok got)
              (mt got
                ((some code)
                  (let [(_ (if sess.stdinOpen (fdClose sess.stdinFd) (ok ())))]
                    (SupervisorState :sessions (removeSession acc.sessions sess.id)
                                     :finished (cons (finishSession sess code nowSec) (removeSession acc.finished sess.id)))))
                ((none) acc)))
            ((err _)
              (SupervisorState :sessions (removeSession acc.sessions sess.id)
                               :finished (cons (finishSession sess 1 nowSec) (removeSession acc.finished sess.id))))))
        state
        state.sessions)

fn runningCount state: SupervisorState -> Int64
  (listLength state.sessions)

fn signalled? r: (Result Unit String) -> Bool
  (mt r ((ok _) true) ((err e) (= e "noProcess")))

fn ! awaitLeaders! pids: (List Int64) deadlineNs: Int64 -> (List Int64)
  (let [(left (filter (fn [(pid Int64)] -> Bool (mt (procWaitPid pid true) ((ok got) (none? got)) ((err _) false))) pids))]
    (if (or (listEmpty? left) (>= (monotonicNs) deadlineNs))
      left
      (do (sleepMs 20) (awaitLeaders! left deadlineNs))))

fn ! killAllSessions! state: SupervisorState -> Bool
  (let [(sessions state.sessions)
        (termed (listAll? (fn [(sess SessionRecord)] -> Bool
                            (let [(closed (if sess.stdinOpen (fdClose sess.stdinFd) (ok ())))]
                              (and (ok? closed) (signalled? (procKill (- 0 sess.pid) "SIGTERM")))))
                          sessions))
        (left (awaitLeaders! (map (fn [(sess SessionRecord)] -> Int64 sess.pid) sessions) (+ (monotonicNs) 2000000000)))
        (killed (listAll? (fn [(sess SessionRecord)] -> Bool (signalled? (procKill (- 0 sess.pid) "SIGKILL"))) sessions))
        (reaped (listAll? (fn [(pid Int64)] -> Bool (ok? (procWaitPid pid false))) left))]
    (and termed (and killed reaped)))

fn finishedLines state: SupervisorState -> String
  (stringJoin (map (fn [(s SessionRecord)] -> String
                     (str s.id " " (stringFromInt64 s.pid) " " (stringFromInt64 s.exitCode) " " (stringFromInt64 s.durationMs) " " s.state "\n"))
                   state.finished)
              "")

fn parseFinishedLine line: String -> (Option SessionRecord)
  (let [(fields (filter (fn [(f String)] -> Bool (not (stringEmpty? f))) (stringSplit (stringTrim line) " ")))]
    (if (!= (listLength fields) 5)
      (none)
      (let [(id (optionOr (listGet fields 0) ""))
            (pid (stringToInt64 (optionOr (listGet fields 1) "")))
            (code (stringToInt64 (optionOr (listGet fields 2) "")))
            (dur (stringToInt64 (optionOr (listGet fields 3) "")))
            (stateVal (optionOr (listGet fields 4) ""))]
        (if (and (w/validSessionId? id) (some? pid) (some? code) (some? dur)
                 (listContains? (list ":completed" ":failed" ":terminated") stateVal))
          (some (SessionRecord :id id :pid (optionOr pid 0) :cmd "" :cwd "" :startTimeSec 0 :state stateVal
                               :exitCode (optionOr code 1) :durationMs (optionOr dur 0)
                               :logPath (str "/tmp/asl-sessions/" id ".log") :stdinFd -1 :stdinOpen false))
          (none)))))

fn loadFinished text: String -> SupervisorState
  (SupervisorState :sessions (list)
                   :finished (fold (fn [(acc (List SessionRecord)) (line String)] -> (List SessionRecord)
                                     (mt (parseFinishedLine line) ((some s) (listAppend acc (list s))) ((none) acc)))
                                   (list)
                                   (stringLines text)))
