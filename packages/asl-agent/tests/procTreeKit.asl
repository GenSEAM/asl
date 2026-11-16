(module aslAgent/tests/procTreeKit
  :x [ProcRow parseRow hostRows! treeIn treeNaming! liveNaming! anyLive! hasArgs? sleeperCmd probeSeesSelf!]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref NODE-BASE-RED :do "a gate child's pid as the gate sees it is not a host pid on Linux: bwrap gives the jail its own pid namespace, so $! and $PPID inside it are small namespace numbers that name kernel threads or unrelated processes outside. The host side finds a fixture's processes instead: every live process whose command line names the fixture root (Leon's form, bwrap's binds, the sleeper's marker argument) and their descendants, read from one ps run of the whole host; the same probe holds on macOS, where the sandbox shares the pid space")

(schema ProcRow (:f pid Int64) (:f ppid Int64) (:f stat String) (:f args String))

fn parseRow line: String -> (Option ProcRow)
  (let [words (filter (fn [w] (not (stringEmpty? w))) (stringSplit (stringTrim line) " "))
        pid (optionOr (stringToInt64 (optionOr (listGet words 0) "")) 0)
        ppid (optionOr (stringToInt64 (optionOr (listGet words 1) "")) -1)]
    (if (or (< (listLength words) 4) (<= pid 0))
      (none)
      (some (ProcRow :pid pid :ppid ppid :stat (optionOr (listGet words 2) "") :args (stringJoin (listDrop words 3) " ")))))

fn live? r: ProcRow -> Bool
  (not (stringStartsWith? r.stat "Z"))

; (:m :ref NODE-BASE-RED :do "-ww keeps the whole command line on both procps and BSD ps; a ps that fails gives no rows, which the callers read as nothing found only together with their own started evidence")
fn ! hostRows! -> (List ProcRow)
  (let [d (fr/runOneLimited (fr/job (list "ps" "-ww" "-eo" "pid=,ppid=,stat=,args=") "/" (fr/childEnv (list))) (fr/limits 20 4))]
    (if (!= d.exit 0)
      (list)
      (fold (fn [acc l] (match (parseRow l) ((some r) (listAppend acc (list r))) ((none) acc))) (list) (stringLines d.out))))

fn closure rows: (List ProcRow) pids: (List Int64) -> (List Int64)
  (let [more (map (fn [r] r.pid) (filter (fn [r] (and (listContains? pids r.ppid) (not (listContains? pids r.pid)))) rows))]
    (if (listEmpty? more) pids (closure rows (listAppend pids more))))

; (:m :ref NODE-BASE-RED :do "the live rows whose command line contains marker, plus every live descendant of them")
fn treeIn rows: (List ProcRow) marker: String -> (List ProcRow)
  (let [alive (filter live? rows)
        seeds (map (fn [r] r.pid) (filter (fn [r] (stringContains? r.args marker)) alive))
        pids (closure alive seeds)]
    (filter (fn [r] (listContains? pids r.pid)) alive))

fn ! treeNaming! marker: String -> (List ProcRow)
  (treeIn (hostRows!) marker)

fn ! liveNaming! marker: String -> (List Int64)
  (map (fn [r] r.pid) (treeNaming! marker))

fn ! anyLive! pids: (List Int64) -> Bool
  (listAny? (fn [r] (and (live? r) (listContains? pids r.pid))) (hostRows!))

fn hasArgs? rows: (List ProcRow) part: String -> Bool
  (listAny? (fn [r] (stringContains? r.args part)) rows)

; (:m :ref NODE-BASE-RED :do "a gate's sleeping child that carries the fixture root on its command line: a shell that cannot exec its last command, so it stays the parent of sleep for the whole nap")
fn sleeperCmd root: String -> String
  (str "sh -c 'sleep 40; :' '" root "'")

; (:m :ref NODE-BASE-RED :do "a positive control for the callers whose claim is that nothing names the root any more: the same probe must see the test process itself, so a ps that failed or printed nothing cannot pass for gone")
fn ! probeSeesSelf! -> Bool
  (listAny? (fn [r] (= r.pid (procSelf))) (hostRows!))
