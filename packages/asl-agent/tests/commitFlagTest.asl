(module aslAgent/tests/commitFlagTest
  :x [runTests]
  :i [(aslAgent/main :a m)])

; (:m :ref LIVELOOP-COMMIT-RED :do "the (:agent ...) form's :commit key is the only way a run asks for a commit: absent or false keeps RunArgs.commit false, true sets it")

fn ! commitOf form: String -> Bool
  (m/runArgsOf (m/parseInvocation form ".").params 600 1200 false).commit

fn ! runTests -> Bool
  (do
    (assert (not (commitOf "(:agent :task \"fix add and COMMIT\")")) "no :commit key: no commit, whatever the task prose says")
    (assert (commitOf "(:agent :task \"t\" :commit true)") ":commit true requests a commit")
    (assert (not (commitOf "(:agent :task \"t\" :commit false)")) ":commit false does not")
    (assert (commitOf "(:agent :task \"t\" :commit :owns (\"a\"))") "a bare :commit before the next key is true, like :dryRun")
    (assert (listContains? (m/acceptedKeys) "commit") ":commit is an accepted key")
    true)
