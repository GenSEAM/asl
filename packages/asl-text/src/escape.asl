(module asl-text/escape :x [UnescapeState escapeAsnStr unescapeAsnStr escapeJsonStr unescapeJsonStr escapeShArg isShSafeArg escapeShCompact] :i [])

(schema UnescapeState (:f out Str) (:f esc Bool))

fn unescapeStringScanner s: Str -> Str
  (let [(chars (stringChars s))
        (init (UnescapeState :out "" :esc false))
        (st (fold (fn [(acc UnescapeState) (c Str)] -> UnescapeState
                    (if acc.esc
                      (let [(emitted (cond ((= c "n") "\n") ((= c "r") "\r") ((= c "t") "\t") ((= c "\"") "\"") ((= c "\\") "\\") (else (str "\\" c))))]
                        (UnescapeState :out (str acc.out emitted) :esc false))
                      (if (= c "\\")
                        (UnescapeState :out acc.out :esc true)
                        (UnescapeState :out (str acc.out c) :esc false))))
                  init
                  chars))]
    (if st.esc (str st.out "\\") st.out))

fn escapeAsnStr s: Str -> Str
  (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\r" "\\r") "\t" "\\t")

fn unescapeAsnStr s: Str -> Str
  (unescapeStringScanner s)

fn escapeJsonStr s: Str -> Str
  (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\r" "\\r") "\x08" "\\b") "\x0c" "\\f") "\t" "\\t")

fn unescapeJsonStr s: Str -> Str
  (unescapeStringScanner s)

fn escapeShArg arg: Str -> Str
  (if (stringEmpty? arg) "''" (if (not (stringContains? arg "'")) (str "'" arg "'") (let [(escaped (stringReplace arg "'" "'\\''"))] (str "'" escaped "'"))))

fn isShSafeArg arg: Str -> Bool
  (let [(trimmed (stringTrim arg))]
    (if (stringEmpty? trimmed)
      false
      (and (not (stringContains? trimmed " "))
           (not (stringContains? trimmed "\""))
           (not (stringContains? trimmed "'"))
           (not (stringContains? trimmed "$"))
           (not (stringContains? trimmed "`"))
           (not (stringContains? trimmed "\\"))
           (not (stringContains? trimmed ";"))
           (not (stringContains? trimmed "&"))
           (not (stringContains? trimmed "|"))
           (not (stringContains? trimmed ">"))
           (not (stringContains? trimmed "<"))
           (not (stringContains? trimmed "("))
           (not (stringContains? trimmed ")"))
           (not (stringContains? trimmed "*"))
           (not (stringContains? trimmed "?"))
           (not (stringContains? trimmed "~"))
           (not (stringContains? trimmed "!")))))

fn escapeShCompact arg: Str -> Str
  (let [(trimmed (stringTrim arg))]
    (if (isShSafeArg trimmed) trimmed (escapeShArg trimmed)))
