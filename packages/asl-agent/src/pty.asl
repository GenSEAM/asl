(module aslAgent/pty :x [PtyResult AnsiState ThoughtEntry PtyPointer makePtyResult formatPtyResult isAnsiTerminator? stripAnsiEscapes ptyStreamBypass sparklineGlyph quantizeSparklinePoint averageList downsampleHelper downsampleMetrics renderSparkline compressMetricsSparkline makeThoughtEntry formatThoughtEntry quarantineThought makePtyPointer formatPtyPointer shouldOffloadPayload? estimateTokenSavings formatPointerDeref] :i [])

(schema PtyResult (:f exitCode I64) (:f durationMs I64) (:f bytesStreamed I64) (:f summary Str))

(schema AnsiState (:f inEsc I64) (:f acc (List Str)))

(schema ThoughtEntry (:f turnId I64) (:f tokens I64) (:f content Str))

(schema PtyPointer (:f id Str) (:f action Str) (:f bytes I64) (:f tokensSaved I64) (:f summary Str))

fn makePtyResult exitCode: I64 durationMs: I64 bytesStreamed: I64 summary: Str -> PtyResult
  (PtyResult :exitCode exitCode :durationMs durationMs :bytesStreamed bytesStreamed :summary summary)

fn formatPtyResult res: PtyResult -> Str
  (str "(:pty-result :exit-code " (stringFromInt64 res.exitCode) " :duration-ms " (stringFromInt64 res.durationMs) " :bytes-streamed " (stringFromInt64 res.bytesStreamed) " :summary \"" res.summary "\")")

fn isAnsiTerminator? c: Str -> Bool
  (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz@~" c)

fn listReverseStr xs: (List Str) -> (List Str)
  (fold (fn [(acc (List Str)) (x Str)] -> (List Str) (cons x acc)) (list) xs)

fn stripAnsiEscapes raw: Str -> Str
  (let [(chars (stringChars raw)) (finalSt (fold (fn [(st AnsiState) (c Str)] -> AnsiState (let [(mode st.inEsc) (acc st.acc)] (if (= mode 0) (if (= c "\u001b") (AnsiState :inEsc 1 :acc acc) (AnsiState :inEsc 0 :acc (cons c acc))) (if (= mode 1) (if (= c "[") (AnsiState :inEsc 2 :acc acc) (if (= c "]") (AnsiState :inEsc 0 :acc (cons "]" (cons "\u001b" acc))) (AnsiState :inEsc 0 :acc (cons c (cons "\u001b" acc))))) (if (= mode 2) (if (isAnsiTerminator? c) (AnsiState :inEsc 0 :acc acc) (AnsiState :inEsc 2 :acc acc)) (AnsiState :inEsc 0 :acc (cons c acc))))))) (AnsiState :inEsc 0 :acc (list)) chars))] (stringJoin (listReverseStr finalSt.acc) ""))

fn ptyStreamBypass rawTerminalStream: Str exitCode: I64 durationMs: I64 -> PtyResult
  (let [(clean (stripAnsiEscapes rawTerminalStream)) (bytes (stringLength rawTerminalStream)) (summary (if (= exitCode 0) "PTY stream completed cleanly" (str "PTY stream failed with exit code " (stringFromInt64 exitCode))))] (PtyResult :exitCode exitCode :durationMs durationMs :bytesStreamed bytes :summary summary))

fn sparklineGlyph level: I64 -> Str
  (if (<= level 0) " " (if (= level 1) "▂" (if (= level 2) "▃" (if (= level 3) "▄" (if (= level 4) "▅" (if (= level 5) "▆" (if (= level 6) "▇" "█")))))))

fn quantizeSparklinePoint val: I64 -> Str
  (if (<= val 0) " " (if (>= val 100) "█" (let [(level (/ (* val 8) 100)) (clamped (if (> level 7) 7 level))] (sparklineGlyph clamped))))

fn averageList xs: (List I64) -> I64
  (let [(len (listLength xs))] (if (<= len 0) 0 (/ (listSum xs) len)))

fn downsampleHelper metrics: (List I64) bucketSize: I64 remaining: I64 offset: I64 -> (List I64)
  (if (<= remaining 0) (list) (let [(chunk (mt (listSlice metrics offset (+ offset bucketSize)) ((some xs) xs) ((none) (list)))) (avg (averageList chunk)) (rest (downsampleHelper metrics bucketSize (- remaining 1) (+ offset bucketSize)))] (cons avg rest)))

fn downsampleMetrics metrics: (List I64) targetPoints: I64 -> (List I64)
  (let [(total (listLength metrics))] (if (or (<= total targetPoints) (<= targetPoints 0)) metrics (let [(bSize (/ total targetPoints))] (if (<= bSize 0) metrics (downsampleHelper metrics bSize targetPoints 0)))))

fn renderSparkline metrics: (List I64) -> Str
  (fold (fn [(acc Str) (m I64)] -> Str (str acc (quantizeSparklinePoint m))) "" metrics)

fn compressMetricsSparkline metrics: (List I64) targetPoints: I64 -> Str
  (renderSparkline (downsampleMetrics metrics targetPoints))

fn makeThoughtEntry turnId: I64 tokens: I64 content: Str -> ThoughtEntry
  (ThoughtEntry :turnId turnId :tokens tokens :content content)

fn formatThoughtEntry entry: ThoughtEntry -> Str
  (str "(:thought :turn-id " (stringFromInt64 entry.turnId) " :tokens " (stringFromInt64 entry.tokens) " :content \"" entry.content "\")")

fn quarantineThought turnId: I64 content: Str -> ThoughtEntry
  (let [(rawToks (/ (stringLength content) 4)) (toks (if (< rawToks 1) 1 rawToks))] (ThoughtEntry :turnId turnId :tokens toks :content content))

fn makePtyPointer id: Str action: Str bytes: I64 tokensSaved: I64 summary: Str -> PtyPointer
  (PtyPointer :id id :action action :bytes bytes :tokensSaved tokensSaved :summary summary)

fn formatPtyPointer ptr: PtyPointer -> Str
  (str "(:ptr :id \"" ptr.id "\" :action \"" ptr.action "\" :bytes " (stringFromInt64 ptr.bytes) " :tokens-saved " (stringFromInt64 ptr.tokensSaved) " :summary \"" ptr.summary "\")")

fn shouldOffloadPayload? bytes: I64 -> Bool
  (> bytes 500)

fn estimateTokenSavings bytes: I64 -> I64
  (let [(toks (/ bytes 4))] (if (< toks 1) 1 toks))

fn formatPointerDeref id: Str data: Str -> Str
  (str "(:ptr :action \"deref\" :id \"" id "\" :bytes " (stringFromInt64 (stringLength data)) " :data \"" data "\")")
