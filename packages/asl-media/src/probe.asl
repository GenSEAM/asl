(module asl-media/probe
  :x [ProbeStream ProbeInfo parseProbe probeArgv ffmpegArgv pathAllowed? inputAllowed! outputAllowed! argBad? whichBin! ffprobeBin! ffmpegBin! probe! runFfmpeg! defaultFfprobe defaultFfmpeg parseRational]
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

fn ! realUnder! p: String roots: (List String) -> Bool
  (match (realPath p)
    ((err _) false)
    ((ok r) (fold (fn [(acc Bool) (root String)] -> Bool
                    (or acc (match (realPath root) ((ok rr) (underRoot? r rr)) ((err _) false))))
                  false roots)))

fn dirOf p: String -> String
  (let [(parts (stringSplit p "/"))
        (keep (listTake parts (- (listLength parts) 1)))
        (joined (stringJoin keep "/"))]
    (if (stringEmpty? joined) "/" joined))

; (:m :ref U-MEDIA :do "symlinks are resolved before the root check: an input must exist and its real path sit under a real root")
fn ! inputAllowed! p: String roots: (List String) -> Bool
  (and (pathAllowed? p roots) (realUnder! p roots))

; (:m :ref U-MEDIA :do "an output does not exist yet, so its parent directory is resolved instead; an existing output that is a symlink must itself resolve under a root, and a dangling one is refused")
fn ! outputAllowed! p: String roots: (List String) -> Bool
  (and (pathAllowed? p roots)
       (and (realUnder! (dirOf p) roots)
            (match (fileLstat p)
              ((ok st) (if st.isSymlink (realUnder! p roots) true))
              ((err _) true))))

fn runLabelled! argv: (List String) lim: fr/Limits -> (Result String String)
  (let [(o (fr/runGuarded argv "." (list) lim))]
    (cond
      (o.timedOut (err (str "mediaTimeout: " (stringFromInt64 lim.timeoutMs) "ms " (stringJoin argv " "))))
      ((!= o.exitCode 0) (err (str "mediaExit: code " (stringFromInt64 o.exitCode) ": " o.stderr)))
      (else (ok o.stdout))))

fn ! probe! bin: String path: String roots: (List String) timeoutS: Int64 -> (Result ProbeInfo String)
  (if (not (inputAllowed! path roots))
    (err (str "mediaPathNotAllowed: " path))
    (match (runLabelled! (probeArgv bin path) (fr/limits timeoutS 64))
      ((err e) (err e))
      ((ok out) (parseProbe out))))

; (:m :ref U-MEDIA :do "args are options only: inputs and outputs come from the checked lists and are placed by this function, so a path, a protocol, a file-reading filter, an overwrite flag or a bare file name in args is refused rather than guessed at")
fn nameChar? b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57)) (or (and (>= b 65) (<= b 90)) (or (and (>= b 97) (<= b 122)) (or (= b 46) (or (= b 95) (= b 45))))))

fn allNameChars? bs: Bytes i: Int64 -> Bool
  (cond ((>= i (bytesLength bs)) true)
        ((not (nameChar? (bytesGet bs i))) false)
        (else (allNameChars? bs (+ i 1))))

fn anyNonDigit? bs: Bytes i: Int64 -> Bool
  (cond ((>= i (bytesLength bs)) false)
        ((or (< (bytesGet bs i) 48) (> (bytesGet bs i) 57)) true)
        (else (anyNonDigit? bs (+ i 1))))

; (:m :ref U-MEDIA :do "a token of only name characters with a dot and an extension that is not all digits, such as out.mp4; 1.5 and libx264 pass")
fn bareFileName? tok: String -> Bool
  (let [(parts (stringSplit tok "."))
        (ext (optionOr (listGet parts (- (listLength parts) 1)) ""))]
    (and (> (listLength parts) 1)
         (and (not (stringStartsWith? tok "-"))
              (and (allNameChars? (stringToBytes tok) 0)
                   (anyNonDigit? (stringToBytes ext) 0)))))

fn anyPrefix? tok: String ks: (List String) -> Bool
  (fold (fn [(acc Bool) (k String)] -> Bool (or acc (stringStartsWith? tok k))) false ks)

fn anyInfix? tok: String ks: (List String) -> Bool
  (fold (fn [(acc Bool) (k String)] -> Bool (or acc (stringContains? tok k))) false ks)

fn argBad? tok: String inputs: (List String) outputs: (List String) -> Bool
  (if (or (listContains? inputs tok) (listContains? outputs tok))
    false
    (or (listContains? (list "-y" "-i" "-report" "-progress" "-vstats_file" "-passlogfile" "-attach" "-dump_attachment" "-sdp_file" "-filter_script" "-filter_complex_script" "-protocol_whitelist") tok)
        (stringContains? tok "/")
        (anyPrefix? tok (list "." "~" "pipe:" "file:" "concat:" "subfile:" "tcp:" "udp:" "http" "data:"))
        (anyInfix? tok (list "movie=" "subtitles=" "ass=" "filename=" "fontfile=" "textfile=" "@"))
        (bareFileName? tok)))

fn ! pathOnPath! dirs: (List String) name: String -> Option String
  (match (listHead dirs)
    ((none) none)
    ((some d)
      (let [(c (str d "/" name))]
        (if (and (not (stringEmpty? d)) (fileExists? c))
          (some c)
          (pathOnPath! (optionOr (listTail dirs) (list)) name)))))

; (:m :ref U-MEDIA :do "first PATH entry holding a file of that name, else the fallback; the caller passes the result as bin, so a test never depends on PATH")
fn ! whichBin! name: String fallback: String -> String
  (optionOr (pathOnPath! (stringSplit (optionOr (envGet "PATH") "") ":") name) fallback)

fn ! ffprobeBin! -> String
  (whichBin! "ffprobe" (defaultFfprobe))

fn ! ffmpegBin! -> String
  (whichBin! "ffmpeg" (defaultFfmpeg))

fn inputArgs ins: (List String) -> (List String)
  (fold (fn [(acc (List String)) (p String)] -> (List String) (listAppend acc (list "-i" p))) (list) ins)

fn ! runFfmpeg! bin: String inputs: (List String) outputs: (List String) args: (List String) roots: (List String) timeoutS: Int64 -> (Result String String)
  (let [(badIn (listHead (filter (fn [(p String)] -> Bool (not (inputAllowed! p roots))) inputs)))
        (badOut (listHead (filter (fn [(p String)] -> Bool (not (outputAllowed! p roots))) outputs)))
        (badArg (listHead (filter (fn [(t String)] -> Bool (argBad? t inputs outputs)) args)))]
    (match badIn
      ((some bad) (err (str "mediaPathNotAllowed: " bad)))
      ((none)
        (match badOut
          ((some bad) (err (str "mediaPathNotAllowed: " bad)))
          ((none)
            (match badArg
              ((some bad) (err (str "mediaArgRefused: " bad)))
              ((none) (runLabelled! (ffmpegArgv bin (listAppend (listAppend (inputArgs inputs) args) outputs)) (fr/limits timeoutS 64)))))))))
