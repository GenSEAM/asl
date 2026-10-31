(module asl-proc/jobPoolFenceTest :x [runTests] :i [(jobPool :a jp)])

; (:m :ref NODE2-SIGSTOP-RC :do "the package copy of the tree killer under the node2 snapshot of 2026-10-30 in miniature: user manager 19144, sshd 500/501, login shell 600, a job wrapper 700 whose group holds the killer 720 and its parent 710, the killer's job 740 with 741 and 742 (742 in the conductor's group 800), and a foreign sleeper 900 with ppid 1")
fn nodeSnapshot -> String
  "    1     0     1 S 3-00:00:00 launchd\n19144     1 19144 S 3-00:00:00 systemd\n  500     1   500 S 3-00:00:00 sshd\n  501   500   501 S 01:00:00 sshd-session\n  600   501   600 S 01:00:00 bash\n  700 19144   700 S 30:00 perl\n  710   700   700 S 30:00 sh\n  720   710   700 S 30:00 test\n  730   720   700 S 05:00 sleep\n  740   720   740 S 05:00 sh\n  741   740   740 S 04:00 sleep\n  742   741   800 S 04:00 sleep\n  800 19144   800 S 2-00:00:00 conductor\n  810   800   800 S 2-00:00:00 writer\n  900     1   900 S 2-00:00:00 sleep\n  910   900   900 S 2-00:00:00 sleep\n"

; (:m :ref KILL-SETSID-ESCAPEE :do "taken at second 1000000: a job 740 (5 min old) whose daemon 950 did setsid and reparented to init 3 min ago, with child 951, pinned in known with its birth; a foreign sleeper 900 (2 days old) pinned too; pid 970 now held by a 1 min old stranger while known pins the earlier holder of 970 (born 190 s before it); a younger stranger 960 that is not known; the killer is 720")
fn escapeeSnapshot -> String
  "  720   710   700 S 30:00 test\n  740   720   740 S 05:00 sh\n  741   740   740 S 04:00 sleep\n  950     1   950 S 03:00 daemon\n  951   950   950 S 03:00 worker\n  900     1   900 S 2-00:00:00 sleep\n  910   900   900 S 2-00:00:00 sleep\n  960     1   960 S 02:00 other\n  970     1   970 S 01:00 reused\n"

fn testEscapee -> Bool
  (let [(procs (jp/procsAt (escapeeSnapshot) 1000000))
        (known (list 741 (jp/pinOf 950 999820) (jp/pinOf 900 827200) (jp/pinOf 970 999750)))
        (t (jp/treeOf procs 740 (list 740 950 900 960 970) known 720))
        (members (pairFirst t))
        (groups (pairSecond t))
        (bare (jp/treeOf procs 740 (list 740 950) (list 741 950) 720))]
    (do (assert (listContains? members 950) (str "a pinned escapee younger than the job, leading its own live group, is killed: " members))
        (assert (listContains? members 951) (str "and so is its child: " members))
        (assert (listContains? groups 950) (str "the escapee's group is signalled: " groups))
        (refute (listContains? members 900) "a pinned foreign sleeper older than the job is spared")
        (refute (listContains? members 910) "nor its child")
        (refute (listContains? groups 900) "nor its group")
        (refute (listContains? members 970) "a known pid now held by a younger unrelated process (birth no longer matches the pin) is spared")
        (refute (listContains? groups 970) "nor is its group signalled")
        (refute (listContains? members 960) "a younger process that was never known is spared")
        (refute (listContains? (pairFirst bare) 950) "a bare known pid without a recorded birth never qualifies as an escapee")
        true))

fn testPinBits -> Bool
  (let [(procs (jp/procsAt (escapeeSnapshot) 1000000))
        (wide (jp/treeOf procs 740 (list 740 950) (list 741 (jp/pinOf (+ 8388608 950) 999819)) 720))]
    (do (assert (= (jp/pinOf 8388608 5) 8388608) "a pid at 2^23 stays bare, it does not fit the pin")
        (assert (= (jp/pinOf 0 5) 0) "pid 0 stays bare")
        (assert (= (jp/pinOf 8388607 5) (+ (* 5 8388608) 8388607)) "the largest pid below 2^23 is packed")
        (refute (listContains? (pairFirst wide) 950) "a known pid of 2^23+950 never aliases to pid 950 born a second later")
        true))

fn testFence -> Bool
  (let [(procs (jp/procsOf (nodeSnapshot)))
        (pids (map (fn [(p jp/Proc)] -> Int64 p.pid) procs))
        (zero (jp/treeOf procs 0 (list) (list) 720))
        (init (jp/treeOf procs 1 (list) (list) 720))
        (parent (jp/treeOf procs 710 (list 700) (list 720 730) 720))
        (job (jp/treeOf procs 740 (list 900 19144 600 700 800 740) (list 900 910 19144 600 710 800) 720))
        (members (pairFirst job))
        (groups (pairSecond job))]
    (do (refute (listContains? pids 19144) "the user manager (comm systemd) is never a snapshot row")
        (refute (listContains? pids 501) "an sshd session process is never a snapshot row")
        (assert (listEmpty? (pairFirst zero)) (str "a root of 0 has an empty tree, not every process: " (pairFirst zero)))
        (assert (listEmpty? (pairFirst init)) (str "a root of 1 has an empty tree, not every orphan of init: " (pairFirst init)))
        (assert (listEmpty? (pairFirst parent)) (str "the killer's own parent as root gives an empty tree: " (pairFirst parent)))
        (assert (and (= (listLength members) 2) (and (listContains? members 741) (listContains? members 742))) (str "the job's tree is its two children and nothing else: " members))
        (refute (listContains? members 900) "a foreign sleeper with ppid 1 in known is not stopped")
        (refute (listContains? members 810) "a member in the conductor's group does not pull the conductor's writer in")
        (assert (and (= (listLength groups) 1) (listContains? groups 740)) (str "only the job's own group is signalled: " groups))
        true))

fn ! runTests -> Bool
  (do (assert (testEscapee) "the package tree killer takes a known escapee younger than the job and spares an older foreign process")
      (assert (testPinBits) "a pid outside the pin bits stays bare and never aliases another pid")
      (assert (testFence) "the package tree killer never reaches pid 0, itself, its ancestors, a foreign group or a user manager")
      true)
