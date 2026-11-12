(module asl-media/tests/probeTest
  :x [runTests]
  :i [(asl-media/probe :a pr)])

fn fixture! name: String -> String
  (match (fileReadString (str "asl/packages/asl-media/tests/fixtures/" name))
    ((ok s) s)
    ((err _) ""))

fn ! testParseFixture! -> Bool
  (match (pr/parseProbe (fixture! "clipProbe.json"))
    ((err e) (do (assert false (str "fixture parses: " e)) false))
    ((ok info)
      (let [(v (optionOr (listGet info.streams 0) (pr/ProbeStream :index -1 :kind "" :codec "" :pixFmt "" :width 0 :height 0 :fpsNum 0 :fpsDen 0 :sampleRate 0 :channels 0 :bitRate 0 :durationS 0.0 :tags (list))))
            (a (optionOr (listGet info.streams 1) (pr/ProbeStream :index -1 :kind "" :codec "" :pixFmt "" :width 0 :height 0 :fpsNum 0 :fpsDen 0 :sampleRate 0 :channels 0 :bitRate 0 :durationS 0.0 :tags (list))))]
        (do
          (assert (= (listLength info.streams) 2) "two streams")
          (assert (stringContains? info.container "mp4") "container names mp4")
          (assert (= v.kind "video") "stream 0 is video")
          (assert (= v.codec "h264") "video codec")
          (assert (= v.pixFmt "yuv420p") "pix_fmt")
          (assert (and (= v.width 64) (= v.height 48)) "video size")
          (assert (and (= v.fpsNum 30000) (= v.fpsDen 1001)) "fps stays the rational 30000/1001")
          (assert (= a.kind "audio") "stream 1 is audio")
          (assert (and (= a.sampleRate 44100) (= a.channels 1)) "audio rate and channels")
          (assert (> info.durationS 0.9) "format duration parsed as a float")
          (assert (= (optionOr (listHead (map pairSecond (filter (fn [(kv (Pair String String))] -> Bool (= (pairFirst kv) "major_brand")) info.tags))) "") "isom") "format tags surface")
          true))))

fn ! testRational! -> Bool
  (do
    (assert (= (pairFirst (pr/parseRational "24/1")) 24) "24/1 numerator")
    (assert (= (pairSecond (pr/parseRational "0/0")) 0) "0/0 is unknown, no division")
    (assert (= (pairSecond (pr/parseRational "abc")) 0) "garbage is unknown")
    (assert (= (pairFirst (pr/parseRational "5/0")) 0) "a zero denominator drops the numerator too")
    true)

fn ! testParseErrors! -> Bool
  (do
    (assert (stringStartsWith? (optionOr (err->option (pr/parseProbe "{bad")) "x") "mediaParse") "bad json labelled")
    (assert (err? (pr/parseProbe "{\"format\":{}}")) "missing streams is an err")
    true)

fn err->option r: (Result pr/ProbeInfo String) -> (Option String)
  (match r ((err e) (some e)) ((ok _) none))

fn ! testArgv! -> Bool
  (let [(a (pr/ffmpegArgv "ffmpeg" (list "-i" "x")))]
    (do
      (assert (= (optionOr (listGet a 1) "") "-nostdin") "ffmpeg argv carries -nostdin first")
      (assert (= (optionOr (listGet (pr/probeArgv "ffprobe" "/a/b") 6) "") "-show_streams") "ffprobe asks for streams")
      true))

fn ! testAllowlist! -> Bool
  (let [(roots (list "/work/media" "/tmp/x/"))]
    (do
      (assert (pr/pathAllowed? "/work/media/a.mp4" roots) "inside root")
      (assert (pr/pathAllowed? "/tmp/x/a.mp4" roots) "root with trailing slash")
      (assert (not (pr/pathAllowed? "/work/mediaX/a.mp4" roots)) "prefix sibling refused")
      (assert (not (pr/pathAllowed? "/work/media/../etc/passwd" roots)) "dotdot refused")
      (assert (not (pr/pathAllowed? "media/a.mp4" roots)) "relative refused")
      (assert (not (pr/pathAllowed? "-" roots)) "stdin marker refused")
      (assert (stringStartsWith? (optionOr (err->option (pr/probe! "/nonexistent/ffprobe" "/etc/passwd" roots 5)) "") "mediaPathNotAllowed") "probe refuses before spawn: a missing binary is not reached")
      (assert (stringStartsWith? (optionOr (match (pr/runFfmpeg! "/nonexistent/ffmpeg" (list "/work/media/a" "/etc/passwd") (list) (list) roots 5) ((err e) (some e)) ((ok _) none)) "") "mediaPathNotAllowed") "ffmpeg refuses a bad input before spawn")
      true))

; (:m :ref U-MEDIA :do "a runtime-built tree: root holds ok.mp4 and a symlink esc to a sibling directory outside the root; nothing is spawned, only the allowlist is asked")
fn ! testSymlinks! -> Bool
  (let [(base "/tmp/aslMediaSymTest")
        (root (str base "/root"))
        (outside (str base "/outside"))
        (_ (dirCreate base))
        (_ (dirCreate root))
        (_ (dirCreate outside))
        (_ (fileWrite (str root "/ok.mp4") "x"))
        (_ (fileWrite (str outside "/a.mp4") "x"))
        (_ (pathRemove (str root "/esc")))
        (_ (pathSymlink outside (str root "/esc")))
        (_ (pathRemove (str root "/dangling.mp4")))
        (_ (pathSymlink (str outside "/missing.mp4") (str root "/dangling.mp4")))
        (roots (list root))
        (viaOut (pr/runFfmpeg! "/nonexistent/ffmpeg" (list (str root "/ok.mp4")) (list (str root "/esc/o.mp4")) (list) roots 5))
        (outOfRoot (pr/runFfmpeg! "/nonexistent/ffmpeg" (list (str root "/ok.mp4")) (list (str outside "/o.mp4")) (list) roots 5))
        (viaDangling (pr/runFfmpeg! "/nonexistent/ffmpeg" (list (str root "/ok.mp4")) (list (str root "/dangling.mp4")) (list) roots 5))
        (goodOut (pr/runFfmpeg! "/nonexistent/ffmpeg" (list (str root "/ok.mp4")) (list (str root "/new.mp4")) (list) roots 5))]
    (do
      (assert (pr/inputAllowed! (str root "/ok.mp4") roots) "a real file under the root passes")
      (assert (not (pr/inputAllowed! (str root "/esc/a.mp4") roots)) "a symlinked directory pointing outside is refused though the path is lexically inside")
      (assert (not (pr/inputAllowed! (str root "/missing.mp4") roots)) "a missing input is refused")
      (assert (stringStartsWith? (optionOr (errS viaOut) "") "mediaPathNotAllowed") "an output through the escaping symlink is refused before spawn")
      (assert (stringStartsWith? (optionOr (errS outOfRoot) "") "mediaPathNotAllowed") "an output outside every root is refused before spawn")
      (assert (stringStartsWith? (optionOr (errS viaDangling) "") "mediaPathNotAllowed") "a dangling symlink output is refused")
      (assert (not (stringStartsWith? (optionOr (errS goodOut) "") "mediaPathNotAllowed")) "an output in the root passes the allowlist and reaches the spawn")
      (let [(_ (pathRemove (str root "/esc")))
            (_ (pathRemove (str root "/dangling.mp4")))
            (_ (pathRemove (str root "/ok.mp4")))
            (_ (pathRemove (str outside "/a.mp4")))
            (_ (pathRemove root))
            (_ (pathRemove outside))
            (_ (pathRemove base))]
        true)))

fn ! testArgs! -> Bool
  (let [(roots (list "/tmp"))
        (ins (list))
        (outs (list))
        (bad! (fn [(args (List String))] -> Bool
                (stringStartsWith? (optionOr (errS (pr/runFfmpeg! "/nonexistent/ffmpeg" ins outs args roots 5)) "") "mediaArgRefused")))]
    (do
      (assert (bad! (list "/tmp/x.mp4")) "an absolute path in args is refused before spawn")
      (assert (bad! (list "../x")) "a relative escape in args is refused")
      (assert (bad! (list "~/x")) "a home path in args is refused")
      (assert (bad! (list "-y")) "-y is refused, overwrite is not the caller's to ask for")
      (assert (bad! (list "-i" "x")) "-i in args is refused, inputs are a checked list")
      (assert (bad! (list "out.mp4")) "a bare output file name in args is refused")
      (assert (bad! (list "-vf" "movie=a.png[x]")) "a file-reading filter is refused")
      (assert (bad! (list "-f" "pipe:1")) "a protocol token is refused")
      (assert (not (bad! (list "-c:v" "libx264" "-r" "1.5" "-vf" "scale=64:48"))) "plain options pass the arg check and reach the spawn")
      (assert (bad! (list "-report")) "an option that writes a log file is refused")
      true))

fn ! testWhich! -> Bool
  (do
    (assert (stringEndsWith? (pr/whichBin! "sh" "/nowhere/sh") "/sh") "a name on PATH resolves to a PATH entry")
    (assert (= (pr/whichBin! "noSuchBinaryAslMedia" "/fallback/x") "/fallback/x") "an absent name falls back")
    true)

fn ! testSpawnLabels! -> Bool
  (do
    (assert (stringStartsWith? (optionOr (err->option (pr/probe! "/bin/false" "/tmp/x" (list "/tmp") 5)) "") "mediaExit") "non-zero exit is labelled")
    (testHang!)
    true)

; (:m :ref U-MEDIA :do "the hung child is a runtime-written script that also backgrounds a grandchild; only the group kill returns before the sleeps end")
fn ! testHang! -> Bool
  (let [(script "/tmp/aslMediaHang.sh")
        (_ (fileWrite script "#!/bin/sh\nsleep 20 &\nsleep 20\n"))
        (_ (fileChmod script 493))
        (t0 (monotonicNs))
        (r (pr/probe! script "/tmp/x" (list "/tmp") 1))
        (ms (/ (- (monotonicNs) t0) 1000000))
        (_ (pathRemove script))]
    (do
      (assert (stringStartsWith? (optionOr (err->option r) "") "mediaTimeout") "a hung child is killed at the timeout")
      (assert (< ms 8000) "the kill does not wait for the grandchild")
      true))

fn ! testLiveProbe! -> Bool
  (if (not (fileExists? (pr/defaultFfprobe)))
    (do (print "(:skip :test liveProbe :why ffprobe absent)") true)
    (match (pr/probe! (pr/defaultFfprobe) "/etc/hosts" (list "/") 10)
      ((ok _) (do (assert false "a non-media file must fail") false))
      ((err e) (do (assert (stringStartsWith? e "mediaExit") "ffprobe on a non-media file is a labelled exit err") true))))

fn ! runTests -> Bool
  (do
    (testParseFixture!)
    (testRational!)
    (testParseErrors!)
    (testArgv!)
    (testAllowlist!)
    (testSymlinks!)
    (testArgs!)
    (testWhich!)
    (testSpawnLabels!)
    (testLiveProbe!)
    true)

fn errS r: (Result String String) -> (Option String)
  (match r ((err e) (some e)) ((ok _) none))
