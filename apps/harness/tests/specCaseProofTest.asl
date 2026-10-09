(module aslHarness/tests/specCaseProofTest
  :x [runTests violations gateCommand normSpace opaqueLine? loopProbe]
  :i [(caseProofKit :a kit) (asl-forms/gate :a gate)])

fn row id: String file: String old: String new: String -> kit/Violation
  (kit/Violation :name id :files (list file) :old old :new new)

fn violations -> (List kit/Violation)
  (list (row "c1" "src/freight/planner.py" "def split_shipment(parcels, max_weight_grams, carrier_code):" "def split_shipment(parcels, carrier_code, max_weight_grams):")
        (row "c2" "src/freight/planner.py" "import logging\n" "import logging\nfrom . import legacy\n")
        (row "c3" "src/freight/planner.py" "\"ERR_PARCEL_TOO_HEAVY\"" "\"ERR_OVERWEIGHT\"")
        (row "c4" "src/freight/tariffs.py" "APPEND" "\n# reviewed\n")
        (row "c5" "src/freight/planner.py" "    Parcels are never reordered.\n" "")
        (row "c6" "src/freight/planner.py" "\"split batch=%d parcels=%d grams=%d\"" "\"split batch=%d: %d parcels, %d g\"")
        (row "c7" "src/freight/planner.py" "MAX_PARCELS_PER_BATCH = 12" "MAX_PARCELS_PER_BATCH = 20")
        (row "c8" "CHANGELOG.md" "- planner: split_shipment" "- split_shipment")
        (row "c9" "src/freight/__init__.py" "    \"split_shipment\",\n" "")
        (row "c10" "src/freight/planner.py" "\n                        or current[-1].fragile != parcel.fragile)" ")"))

fn gateCommand task: String -> String
  (optionOr (listHead (map (fn [(l String)] -> String (optionOr (stringSlice l 11 (- (stringLength l) 2)) ""))
                           (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "  :gates (\"") (stringEndsWith? l "\")"))) (stringSplit task "\n"))))
            "")

fn normSpace s: String -> String
  (stringJoin (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringReplace (stringReplace (stringReplace (stringReplace s "`" "") "\n" " ") "\t" " ") "\r" " ") " ")) " ")

fn opaqueLine? l: String -> Bool
  (or (listContains? (fold (fn [(acc (List String)) (id String)] -> (List String) (listAppend acc (list (str "ok " id) (str "FAIL " id))))
                           (list) (list "f1" "f2" "f3" "f4" "f5" "f6" "f7" "c1" "c2" "c3" "c4" "c5" "c6" "c7" "c8" "c9" "c10"))
                     l)
      (kit/gateLine? "constraintsFromSpec" l))

fn ! filesUnder! dir: String rel: String -> (List String)
  (fold (fn [(acc (List String)) (n String)] -> (List String)
          (let [(r (if (stringEmpty? rel) n (str rel "/" n)))
                (p (str dir "/" r))]
            (mt (fileLstat p)
              ((err _) acc)
              ((ok st) (cond
                         (st.isDir (listAppend acc (filesUnder! dir r)))
                         (st.isFile (listAppend acc (list r)))
                         (else acc))))))
        (list) (listSort (resultOr (dirList (if (stringEmpty? rel) dir (str dir "/" rel))) (list))))

fn loopProbe -> String
  (str "import os, shutil, sys, tempfile\n"
       "sys.path.insert(0, os.path.join(sys.argv[1], 'scripts', 'agentLoop'))\n"
       "import loop\n"
       "ctx = int(sys.argv[2])\n"
       "keep = loop.TRANSCRIPT_KEEP_RECENT\n"
       "class Recorder:\n"
       "    def __init__(self, replies):\n"
       "        self.replies, self.sent, self.last_timing = list(replies), [], None\n"
       "    def next_turn(self, system_prompt, user_message):\n"
       "        self.sent.append(user_message)\n"
       "        return self.replies.pop(0) if self.replies else '(:done)'\n"
       "reads = ['docs/SPEC.md', 'src/freight/models.py', 'src/freight/units.py', 'src/freight/tariffs.py',\n"
       "         'src/freight/planner.py', 'src/freight/__init__.py', 'CHANGELOG.md']\n"
       "p = Recorder(['(:step :op \"read\" :file \"%s\")' % f for f in reads])\n"
       "journal = os.path.join(tempfile.mkdtemp(prefix='asl_specproof_j_'), 't.journal')\n"
       "loop.run_loop(p, 'Implement split_shipment in src/freight per docs/SPEC.md.', 'implement',\n"
       "              ['src/freight', 'CHANGELOG.md'], [], os.getcwd(), len(reads) + 2, journal,\n"
       "              context_tokens=ctx, model='gemini-3.8-flash')\n"
       "shutil.rmtree(os.path.dirname(journal))\n"
       "has = [('ERR_PARCEL_TOO_HEAVY' in m) for m in p.sent]\n"
       "verdict = (ctx == loop.SMALL_CONTEXT_TOKENS and has[1:keep + 1] == [True] * keep\n"
       "           and len(has) > keep + 1 and not any(has[keep + 1:]))\n"
       "print('cut' if verdict else 'kept', f'smallTier={ctx == loop.SMALL_CONTEXT_TOKENS} keepRecent={keep} carries={has}')\n")

fn ! gitCommit! repo: String -> Bool
  (listAll? (fn [(args (List String))] -> Bool (= (pairFirst (kit/runIn! (cons "git" (cons "-C" (cons repo args))) repo (list))) 0))
            (list (list "init" "-q") (list "add" "-A")
                  (list "-c" "user.email=eval@asl.local" "-c" "user.name=Agent Eval" "commit" "-q" "-m" "initial fixture state")))

fn ! toolchainInto! repo: String root: String -> Bool
  (and (ok? (dirCreate (str repo "/bin")))
       (and (= (gate/runArgv! (list "cp" (str root "/bin/asl") (str repo "/bin/asl")) (none) (none) 60000 0).code 0)
            (and (= (gate/runArgv! (list "cp" "-R" (str root "/scripts") (str repo "/scripts")) (none) (none) 120000 0).code 0)
                 (and (ok? (pathSymlink (str root "/asl") (str repo "/asl")))
                      (if (fileExists? (str root "/bin/asl-core")) (ok? (pathSymlink (str root "/bin/asl-core") (str repo "/bin/asl-core"))) true)))))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (caseDir "tests/agentEval/cases/implement-constraints-from-spec")
        (task (resultOr (fileReadString (str caseDir "/task.asn")) ""))
        (gateCmd (gateCommand task))
        (src (str caseDir "/src/freight"))
        (lines (kit/sourceLines src))
        (modules (kit/sourceModules src))
        (driver (resultOr (fileReadString "harness/src/evalRun.asl") ""))
        (laid (kit/layCase! caseDir "Spec"))
        (l (mt laid ((ok x) x) ((err e) (kit/Laid :top (str "/nonexistent/" e) :repo (str "/nonexistent/" e) :hidden ""))))
        (repo l.repo)
        (hiddenEnv (list (str "ASL_EVAL_HIDDEN=" l.hidden) "PYTHONDONTWRITEBYTECODE=1"))
        (gateArgv (list "sh" "-c" gateCmd))
        (leaked (filter (fn [(f String)] -> Bool
                          (and (!= f "docs/SPEC.md")
                               (let [(t (resultOr (fileReadString (str repo "/" f)) ""))]
                                 (or (stringContains? t "ERR_PARCEL_TOO_HEAVY") (or (stringContains? t "never reordered") (stringContains? t "split batch="))))))
                        (filesUnder! repo "")))
        (specInRepo (fileExists? (str repo "/docs/SPEC.md")))
        (hiddenInRepo (fileExists? (str repo "/hidden")))
        (spec (normSpace (resultOr (fileReadString (str caseDir "/docs/SPEC.md")) "")))
        (taskNorm (normSpace task))
        (marks (list "parcels, max_weight_grams, carrier_code" "other than legacy.py itself imports" "ERR_PARCEL_TOO_HEAVY" "byte-for-byte unchanged"
                     "Parcels are never reordered." "split batch=N parcels=K grams=W" "more than 12 parcels" "- planner: split_shipment"
                     "listed in its __all__" "never mixes fragile and non-fragile"))
        (base (kit/runIn! gateArgv repo hiddenEnv))
        (outLines (kit/outputLines (pairSecond base)))
        (solution (optionOr (envGet "CONSTRAINTS_SPEC_SOLUTION") ""))
        (solved (if (or (stringEmpty? solution) (not (ok? laid)))
                  (list)
                  (kit/solutionProof! l caseDir solution (list "src/freight/planner.py" "src/freight/__init__.py" "CHANGELOG.md")
                                      "constraintsFromSpec" gateArgv hiddenEnv (violations))))
        (ctx (optionOr (kit/intAfter task ":contextTokens ") 0))
        (laidLoop (and (toolchainInto! repo root) (gitCommit! repo)))
        (probe (if laidLoop (kit/runIn! (list "python3" "-c" (loopProbe) root (stringFromInt64 ctx)) repo (list "PYTHONDONTWRITEBYTECODE=1")) (pair 1 "toolchain or git layout failed")))
        (cut (optionOr (listLast (filter (fn [(x String)] -> Bool (or (stringStartsWith? x "cut ") (stringStartsWith? x "kept "))) (kit/outputLines (pairSecond probe)))) (pairSecond probe)))]
    (do
      (println (str "# spec in each message: " cut))
      (kit/removeLaid! l)
      (assert (and (> lines 2000) (>= modules 5)) "srcOver2000LinesInSeveralModules")
      (assert (and (stringContains? driver "(str repo \"/hidden\")") (stringContains? driver "\"ASL_EVAL_HIDDEN_VARS\" \"ASL_EVAL_HIDDEN\"")) "evalRunKeepsHiddenOutOfRepo")
      (assert (and (ok? laid) (and specInRepo (and (not hiddenInRepo) (listEmpty? leaked)))) "constraintsOnlyInSpec")
      (assert (and (listAll? (fn [(m String)] -> Bool (stringContains? spec m)) marks) (not (listAny? (fn [(m String)] -> Bool (stringContains? taskNorm m)) marks))) "tenRequirementsInSpecNoneInTask")
      (assert (and (not (stringEmpty? gateCmd)) (kit/scoresImplement? (resultOr (fileReadString (str caseDir "/truth.asn")) "") gateCmd)) "truthScoresImplement")
      (assert (!= (pairFirst base) 0) "baseExitsNonZero")
      (assert (listAny? (fn [(x String)] -> Bool (and (kit/gateLine? "constraintsFromSpec" x) (stringContains? x ":asserts 17 :failed "))) outLines) "baseRanToGateLine")
      (assert (listAll? opaqueLine? outLines) "baseOutputOpaque")
      (assert (listAll? (fn [(id String)] -> Bool (listContains? outLines (str "FAIL " id))) (list "f1" "f2" "f3" "f4" "f5" "f6" "f7")) "baseBehaviourAllRed")
      (assert (and (listContains? outLines "ok c2") (listContains? outLines "ok c4")) "baseKeepsUntouchedRequirements")
      (assert (stringStartsWith? cut "cut ") "specReadCutAfterKeepRecentTurns")
      (assert (listAll? (fn [(p (Pair String Bool))] -> Bool (pairSecond p)) solved) "solutionPassesAndEachViolationFailsOnlyItsId")
      true))
