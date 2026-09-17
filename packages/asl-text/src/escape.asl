(module asl-text/escape :doc "Canonical Pure AgentScript String Escaping and Wire Serialization Engine." :export [UnescapeState escapeAsnStr unescapeAsnStr escapeJsonStr unescapeJsonStr escapeShArg isShSafeArg escapeShCompact])

schema UnescapeState { out: Str "Accumulated unescaped string buffer" esc: Bool "True if previous character was escape backslash" }

fn unescapeStringScanner s: Str -> Str
  let chars = (string-chars s)
  let init = (UnescapeState :out "" :esc false)
  let st = (fold (fn [(acc UnescapeState) (c Str)] -> UnescapeState (if (.-esc acc) (let emitted = (cond ((= c "n") "\n") ((= c "r") "\r") ((= c "t") "\t") ((= c "\"") "\"") ((= c "\\") "\\") (:else (str "\\" c))) in (UnescapeState :out (str (.-out acc) emitted) :esc false)) (if (= c "\\") (UnescapeState :out (.-out acc) :esc true) (UnescapeState :out (str (.-out acc) c) :esc false)))) init chars)
  if (.-esc st) (str (.-out st) "\\") (.-out st)

fn escapeAsnStr s: Str -> Str
  s |> (string-replace "\\" "\\\\") |> (string-replace "\"" "\\\"") |> (string-replace "\n" "\\n") |> (string-replace "\r" "\\r") |> (string-replace "\t" "\\t")

fn unescapeAsnStr s: Str -> Str
  unescapeStringScanner s

fn escapeJsonStr s: Str -> Str
  s |> (string-replace "\\" "\\\\") |> (string-replace "\"" "\\\"") |> (string-replace "\n" "\\n") |> (string-replace "\r" "\\r") |> (string-replace "\b" "\\b") |> (string-replace "\f" "\\f") |> (string-replace "\t" "\\t")

fn unescapeJsonStr s: Str -> Str
  unescapeStringScanner s

fn escapeShArg arg: Str -> Str
  if (string-empty? arg) "''" (if (not (string-contains? arg "'")) (str "'" arg "'") (let escaped = (string-replace arg "'" "'\\''") in (str "'" escaped "'")))

fn isShSafeArg arg: Str -> Bool
  let trimmed = (string-trim arg)
  if (string-empty? trimmed) false (and (not (string-contains? trimmed " ")) (and (not (string-contains? trimmed "\"")) (and (not (string-contains? trimmed "'")) (and (not (string-contains? trimmed "$")) (and (not (string-contains? trimmed "`")) (and (not (string-contains? trimmed "\\")) (and (not (string-contains? trimmed ";")) (and (not (string-contains? trimmed "&")) (and (not (string-contains? trimmed "|")) (and (not (string-contains? trimmed ">")) (and (not (string-contains? trimmed "<")) (and (not (string-contains? trimmed "(")) (and (not (string-contains? trimmed ")")) (and (not (string-contains? trimmed "*")) (and (not (string-contains? trimmed "?")) (and (not (string-contains? trimmed "~")) (not (string-contains? trimmed "!"))))))))))))))))))

fn escapeShCompact arg: Str -> Str
  let trimmed = (string-trim arg)
  if (isShSafeArg trimmed) trimmed (escapeShArg trimmed)
