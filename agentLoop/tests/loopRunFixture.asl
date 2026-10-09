(module asl/agentLoop/tests/loopRunFixture
  :x [scenarioLines! scenarioCount! scenarioId repoFiles buildScenarioRepo! maskJournal turnRows listOf argStr field]
  :i [(asl/agentLoop/plan :a p) (asl/agentLoop/core :a c) (asl-proc/coreProcess :a cp)])

fn listOf n: p/SexpNode -> (List p/SexpNode)
  (mt n ((p/sexpList xs) xs) ((p/sexpAtom _) (list)) ((p/sexpStr _) (list)))

fn atomOf n: p/SexpNode -> String
  (mt n ((p/sexpAtom a) a) ((p/sexpStr _) "") ((p/sexpList _) ""))

fn argStr n: p/SexpNode -> String
  (mt n ((p/sexpStr s) s) ((p/sexpAtom a) a) ((p/sexpList _) ""))

fn argAt xs: (List p/SexpNode) i: Int64 -> p/SexpNode
  (optionOr (listGet xs i) (p/sexpAtom "nil"))

fn fieldIn xs: (List p/SexpNode) key: String -> p/SexpNode
  (cond
    ((listEmpty? xs) (p/sexpAtom "nil"))
    ((= (atomOf (c/firstOf xs)) key) (argAt xs 1))
    (else (if (listEmpty? (c/restOf xs)) (p/sexpAtom "nil") (fieldIn (c/restOf (c/restOf xs)) key))))

fn field n: p/SexpNode key: String -> p/SexpNode
  (fieldIn (c/restOf (listOf n)) key)

fn parseLine line: String -> (List p/SexpNode)
  (mt (p/planTree line) ((ok ns) ns) ((err _) (list)))

fn ! scenarioLines! path: String -> (List String)
  (filter (fn [line] (stringStartsWith? line "(:scenario "))
          (stringLines (resultOr (fileReadString path) "")))

fn ! scenarioCount! path: String -> Int64
  (let [lines (stringLines (resultOr (fileReadString path) ""))
        header (optionOr (listHead (filter (fn [line] (stringStartsWith? line "(:fixture ")) lines)) "")
        nodes (parseLine header)]
    (optionOr (stringToInt64 (argStr (field (c/firstOf nodes) ":scenarios"))) -1))

fn scenarioId line: String -> String
  (argStr (field (c/firstOf (parseLine line)) ":id"))

fn repoFiles line: String -> (List (Pair String String))
  (let [repo (field (c/firstOf (parseLine line)) ":repo")
        fields (c/restOf (listOf repo))]
    (map (fn [entry]
           (let [pairNodes (listOf entry)]
             (pair (argStr (c/firstOf pairNodes)) (argStr (argAt pairNodes 1))))) fields))

fn ! writeFile! root: String entry: (Pair String String) -> Bool
  (let [path (str root "/" (pairFirst entry))
        made (dirCreate root)]
    (and (ok? made) (ok? (fileWrite path (pairSecond entry)))))

fn withEnv c: cp/ProcessCmd env: (List (Pair String String)) -> cp/ProcessCmd
  (fold (fn [acc kv] (cp/withEnv acc (pairFirst kv) (pairSecond kv))) c env)

fn ! gitStep! root: String args: (List String) env: (List (Pair String String)) -> Bool
  (mt (cp/exec! (cp/withTimeout (cp/withCwd (withEnv (cp/cmd "git" args) env) root) 60000))
    ((ok o) (= o.exitCode 0))
    ((err _) false))

fn ! buildScenarioRepo! root: String line: String -> Bool
  (let [created (ok? (dirCreate root))
        filesOk (fold (fn [ok entry] (and ok (writeFile! root entry))) true (repoFiles line))
        env (list (pair "GIT_AUTHOR_NAME" "loop fixture") (pair "GIT_AUTHOR_EMAIL" "loop-fixture@example.invalid")
                  (pair "GIT_COMMITTER_NAME" "loop fixture") (pair "GIT_COMMITTER_EMAIL" "loop-fixture@example.invalid")
                  (pair "GIT_AUTHOR_DATE" "2000-01-01T00:00:00Z") (pair "GIT_COMMITTER_DATE" "2000-01-01T00:00:00Z"))
        commands (list (list "init" "-q" "-b" "main") (list "config" "user.name" "loop fixture")
                       (list "config" "user.email" "loop-fixture@example.invalid")
                       (list "add" "--all") (list "commit" "-q" "-m" "initial"))
        gitOk (fold (fn [ok args] (and ok (gitStep! root args env))) filesOk commands)]
    (and created gitOk))

fn maskJournal root: String rows: (List String) -> (List String)
  (filter (fn [row] (not (stringStartsWith? row "(:coreHost ")))
    (map (fn [row] (stringReplace row root "<root>")) rows))

fn turnRows journal: (List String) turn: Int64 keys: (List String) -> (List String)
  (let [prefix (str "(:turn " (stringFromInt64 turn) " ")]
    (filter (fn [row]
              (and (stringStartsWith? row prefix)
                   (or (listEmpty? keys) (listAny? (fn [key] (stringContains? row key)) keys))))
            journal))
