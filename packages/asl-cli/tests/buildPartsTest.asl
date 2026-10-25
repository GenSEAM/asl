(module asl-cli/tests/buildPartsTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/system :a sys)
      (asl/packages/asl-cli/src/nativeBuild :a nb)
      (asl-tools/fleet/run :a run)])

; (:m :ref BUILDPAR :do "bin/asl build links through nativeBuild's parts path: a parts build and a one-part build of the same program print the same bytes, the shape the build reports on stderr is the one asked for (flag or .asl.config.asn :native), and dev selects -O1 while the default stays -O2")
fn fixtureSource -> String
  (stringJoin (list
    "(module buildPartsFixture :x [main] :i [])"
    ""
    "(schema Point (:f x Int64) (:f y Int64))"
    ""
    "fn step p: Point i: Int64 -> Point"
    "  (Point :x (+ p.x i) :y (- p.y (* i 3)))"
    ""
    "fn walk p: Point i: Int64 n: Int64 -> Point"
    "  (if (>= i n) p (walk (step p i) (+ i 1) n))"
    ""
    "fn words n: Int64 -> (List String)"
    "  (map (fn [(i Int64)] -> String (str \"w\" (stringFromInt64 (mod (* i 7) 13)))) (range 0 n))"
    ""
    "fn tally xs: (List String) -> (Map String Int64)"
    "  (fold (fn [(m (Map String Int64)) (w String)] -> (Map String Int64) (mapSet m w (+ 1 (optionOr (mapGet m w) 0)))) (mapEmpty) xs)"
    ""
    "fn render m: (Map String Int64) -> String"
    "  (stringJoin (map (fn [(k String)] -> String (str k \"=\" (stringFromInt64 (optionOr (mapGet m k) 0)))) (listSort (mapKeys m))) \",\")"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(p (walk (Point :x 0 :y 0) 0 5000))"
    "        (m (tally (words 400)))]"
    "    (do (println (str p.x \" \" p.y))"
    "        (println (render m))"
    "        (println (stringFromInt64 (fold (fn [(a Int64) (s String)] -> Int64 (+ a (stringLength s))) 0 (words 1000))))"
    "        (ok 0)))"
    "") "\n")

(schema Built (:f build run/Done) (:f run run/Done) (:f err String))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! runIn argv: (List String) cwd: String env: (List String) secs: Int64 -> run/Done
  (run/runOneLimited (run/job argv cwd (run/childEnv env)) (run/limits secs 24))

fn ! buildIn! root: String work: String name: String config: String flags: (List String) -> Built
  (let [(dir (str work "/" name))
        (_ (dirCreate dir))
        (_ (if (stringEmpty? config) (ok ()) (fileWrite (str dir "/.asl.config.asn") config)))
        (src (str dir "/buildPartsFixture.asl"))
        (_ (fileWrite src (fixtureSource)))
        (exe (str dir "/fixture"))
        (errFile (str dir "/build.err"))
        (b (runIn (listAppend (list "/bin/sh" "-c" (str "b=\"$0\"; s=\"$1\"; o=\"$2\"; shift 2; exec \"$b\" build \"$s\" -o \"$o\" \"$@\" 2> " (shellQuote errFile)) (str root "/bin/asl") src exe) flags) root (list) 900))
        (ran (if (= b.exit 0) (runIn (list exe) dir (list) 60) b))]
    (Built :build b :run ran :err (resultOr (fileReadString errFile) "")))

fn linkLine text: String -> String
  (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:build :link ")) (stringLines text))) "")

fn ! testConfigValues -> Bool
  (do (assert (= (nb/nativeKey "(:aslConfig :native (:parts 3 :level :dev))" ":parts") (some "3")) ":native :parts is read from a config")
      (assert (= (nb/nativeKey "(:aslConfig :native (:parts 3 :level :dev))" ":level") (some ":dev")) ":native :level is read from a config")
      (assert (= (nb/nativeKey "(:aslConfig :workspace \"w\")" ":parts") (none)) "a config without :native leaves the parts to the default")
      (assert (= (nb/levelFlag ":dev") (ok "-O1")) "the dev level is -O1")
      (assert (= (nb/levelFlag ":release") (ok "-O2")) "the release level is -O2")
      (assert (err? (nb/levelFlag ":fast")) "an unknown level is an ERR_CONFIG")
      (assert (= (nb/inlineFor (list "-O1")) 0) "dev parts carry no small-body copies")
      (assert (= (nb/inlineFor (list "-O2")) 2000) "release parts carry the small-body copies")
      (assert (= (nb/partsForSize 8 53710457) 8) "the 53.7 MB compiler module splits the full 8 ways")
      (assert (= (nb/partsForSize 8 12000000) 3) "a 12 MB module splits 3 ways, each part keeping 4 MB")
      (assert (= (nb/partsForSize 8 270500) 1) "a 270 KB bench module links whole")
      (assert (= (nb/partsForSize 1 53710457) 1) "one configured part stays one")
      (assert (= (nb/partsValue "4") (ok 4)) "a parts count parses")
      (assert (err? (nb/partsValue "0")) "zero parts is rejected")
      (assert (err? (nb/partsValue "x")) "a non-integer parts count is rejected")
      true)

fn ! testBuilds root: String work: String -> Bool
  (let [(one (buildIn! root work "one" "" (list "--parts" "1")))
        (four (buildIn! root work "four" "" (list "--parts" "4")))
        (plain (buildIn! root work "plain" "" (list)))
        (dev (buildIn! root work "dev" "(:aslConfig :native (:parts 3 :level :dev))" (list)))
        (flagged (buildIn! root work "flagged" "(:aslConfig :native (:parts 3 :level :dev))" (list "--release")))
        (forced (buildIn! root work "forced" "" (list "--parts" "3" "--dev")))
        (want "12497500 -37492500\n")]
    (do (assert (= one.build.exit 0) (str "the one-part build succeeds: " one.build.out one.err))
        (assert (= four.build.exit 0) (str "the four-part build succeeds: " four.build.out four.err))
        (assert (= plain.build.exit 0) (str "the default build succeeds: " plain.build.out plain.err))
        (assert (= dev.build.exit 0) (str "the configured dev build succeeds: " dev.build.out dev.err))
        (assert (= flagged.build.exit 0) (str "the --release build over a dev config succeeds: " flagged.build.out flagged.err))
        (assert (stringStartsWith? one.run.out want) (str "the one-part binary prints the walk result: " one.run.out))
        (assert (= one.run.exit 0) "the one-part binary exits 0")
        (assert (= four.run.exit 0) "the four-part binary exits 0")
        (assert (= four.run.out one.run.out) (str "the four-part binary prints the same bytes as the one-part binary: " four.run.out))
        (assert (= plain.run.out one.run.out) "the default parts binary prints the same bytes")
        (assert (= dev.run.out one.run.out) "the dev binary prints the same bytes")
        (assert (= flagged.run.out one.run.out) "the --release binary prints the same bytes")
        (assert (= one.err "") (str "a one-part -O2 build is silent on stderr as before: " one.err))
        (assert (stringStartsWith? (linkLine four.err) "(:build :link (:parts 4 :opt \"-O2\"") (str "--parts 4 links four parts at -O2: " (linkLine four.err)))
        (assert (stringStartsWith? (linkLine dev.err) "(:build :link (:parts 1 :opt \"-O1\"") (str ":native (:parts 3 :level :dev) links a small program whole at -O1: " (linkLine dev.err)))
        (assert (= flagged.err "") (str "--release overrides the configured dev level, so the build is the silent classic one: " flagged.err))
        (assert (stringStartsWith? (linkLine forced.err) "(:build :link (:parts 3 :opt \"-O1\"") (str "--parts 3 --dev links three parts at -O1 even for a small program: " (linkLine forced.err)))
        (assert (= forced.run.out one.run.out) "the three-part dev binary prints the same bytes")
        (assert (= plain.err "") (str "the default build links a small program whole at -O2, silent as before: " plain.err))
        true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/buildPartsTest." (stringFromInt64 (procSelf))))
        (_ (dirCreate (str root "/.asl/cache")))
        (made (dirCreate work))
        (values (testConfigValues))
        (builds (if (ok? made) (testBuilds root work) false))
        (cleaned (pathRemove work))]
    (do (assert (ok? made) (str "the work directory " work " was created"))
        (assert values "the config values parse")
        (assert builds "the parts builds agree with the one-part build")
        (assert (ok? cleaned) "the work directory was removed")
        true))
