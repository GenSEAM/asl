(module asl-media/probe
  :x [ProbeStream ProbeInfo parseProbe probeArgv ffmpegArgv pathAllowed? probe! runFfmpeg! defaultFfprobe defaultFfmpeg parseRational]
  :i [(asl-json/json :a js) (asl-tools/fleet/run :a fr)])

schema ProbeStream
  (:f index Int64)
  (:f kind String)
  (:f codec String)
  (:f pixFmt String)
  (:f width Int64)
  (:f height Int64)
  (:f fpsNum Int64)
  (:f fpsDen Int64)
  (:f sampleRate Int64)
  (:f channels Int64)
  (:f bitRate Int64)
  (:f durationS Float64)
  (:f tags (List (Pair String String)))

schema ProbeInfo
  (:f container String)
  (:f durationS Float64)
  (:f bitRate Int64)
  (:f size Int64)
  (:f streams (List ProbeStream))
  (:f tags (List (Pair String String)))

fn defaultFfprobe -> String
  "/opt/homebrew/bin/ffprobe"

fn defaultFfmpeg -> String
  "/opt/homebrew/bin/ffmpeg"

; (:m :ref U-MEDIA :do "frame rates stay a numerator and denominator: 30000/1001 as a float would not round trip and a float compare would drift; denominator 0 means unknown")
fn parseRational s: String -> (Pair Int64 Int64)
  (let [(ws (stringSplit s "/"))]
    (if (= (listLength ws) 2)
      (match (stringToInt64 (optionOr (listGet ws 0) ""))
        ((none) (pair 0 0))
        ((some n)
          (match (stringToInt64 (optionOr (listGet ws 1) ""))
            ((none) (pair 0 0))
            ((some d) (if (> d 0) (pair n d) (pair 0 0))))))
      (pair 0 0)))

fn strField o: js/Json key: String -> String
  (match (js/jsonGet o key)
    ((some (js/jstr s)) s)
    ((some (js/jint i)) (stringFromInt64 i))
    (_ ""))

fn intField o: js/Json key: String -> Int64
  (match (js/jsonGet o key)
    ((some (js/jint i)) i)
    ((some (js/jstr s)) (optionOr (stringToInt64 s) 0))
    (_ 0))

fn floatField o: js/Json key: String -> Float64
  (match (js/jsonGet o key)
    ((some (js/jstr s)) (optionOr (stringToFloat64 s) 0.0))
    ((some (js/jfloat f)) f)
    ((some (js/jnum f)) f)
    ((some (js/jint i)) (int64ToFloat64 i))
    (_ 0.0))

fn tagsOf o: js/Json -> (List (Pair String String))
  (match (js/jsonGet o "tags")
    ((some (js/jobj kvs))
      (map (fn [(kv (Pair String js/Json))] -> (Pair String String)
             (pair (pairFirst kv)
                   (match (pairSecond kv) ((js/jstr s) s) (_ ""))))
           kvs))
    (_ (list)))

fn streamOf o: js/Json -> ProbeStream
  (let [(fps (parseRational (strField o "r_frame_rate")))]
    (ProbeStream :index (intField o "index") :kind (strField o "codec_type") :codec (strField o "codec_name")
      :pixFmt (strField o "pix_fmt") :width (intField o "width") :height (intField o "height")
      :fpsNum (pairFirst fps) :fpsDen (pairSecond fps)
      :sampleRate (intField o "sample_rate") :channels (intField o "channels")
      :bitRate (intField o "bit_rate") :durationS (floatField o "duration") :tags (tagsOf o)))

fn parseProbe text: String -> (Result ProbeInfo String)
  (match (js/jsonParse text)
    ((err e) (err (str "mediaParse: " e)))
    ((ok root)
      (match (js/jsonGet root "streams")
        ((some (js/jarr xs))
          (let [(fmt (optionOr (js/jsonGet root "format") (js/jobj (list))))]
            (ok (ProbeInfo :container (strField fmt "format_name") :durationS (floatField fmt "duration")
                  :bitRate (intField fmt "bit_rate") :size (intField fmt "size")
                  :streams (map streamOf xs) :tags (tagsOf fmt)))))
        (_ (err "mediaParse: no streams array")))))

fn probeArgv bin: String path: String -> (List String)
  (list bin "-v" "error" "-print_format" "json" "-show_format" "-show_streams" path)

; (:m :ref U-MEDIA :do "-nostdin first so a child that wants a tty prompt never blocks on the parent's stdin; -y only through the caller's args, never implied")
fn ffmpegArgv bin: String args: (List String) -> (List String)
  (cons bin (cons "-nostdin" (cons "-hide_banner" args)))

fn hasDotDot? segs: (List String) -> Bool
  (fold (fn [(acc Bool) (s String)] -> Bool (or acc (= s ".."))) false segs)

fn underRoot? path: String root: String -> Bool
  (or (= path root) (stringStartsWith? path (if (stringEndsWith? root "/") root (str root "/"))))

fn pathAllowed? path: String roots: (List String) -> Bool
  (and (stringStartsWith? path "/")
       (not (hasDotDot? (stringSplit path "/")))
       (not (stringContains? path "\x00"))
       (fold (fn [(acc Bool) (r String)] -> Bool (or acc (underRoot? path r))) false roots))

fn runLabelled! argv: (List String) lim: fr/Limits -> (Result String String)
  (let [(o (fr/runGuarded argv "." (list) lim))]
    (cond
      (o.timedOut (err (str "mediaTimeout: " (stringFromInt64 lim.timeoutMs) "ms " (stringJoin argv " "))))
      ((!= o.exitCode 0) (err (str "mediaExit: code " (stringFromInt64 o.exitCode) ": " o.stderr)))
      (else (ok o.stdout))))

fn ! probe! bin: String path: String roots: (List String) timeoutS: Int64 -> (Result ProbeInfo String)
  (if (not (pathAllowed? path roots))
    (err (str "mediaPathNotAllowed: " path))
    (match (runLabelled! (probeArgv bin path) (fr/limits timeoutS 64))
      ((err e) (err e))
      ((ok out) (parseProbe out))))

fn ! runFfmpeg! bin: String inputs: (List String) args: (List String) roots: (List String) timeoutS: Int64 -> (Result String String)
  (match (listHead (filter (fn [(p String)] -> Bool (not (pathAllowed? p roots))) inputs))
    ((some bad) (err (str "mediaPathNotAllowed: " bad)))
    ((none) (runLabelled! (ffmpegArgv bin args) (fr/limits timeoutS 64))))
