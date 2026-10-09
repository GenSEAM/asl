(module asl-proc/reducer :x [ReductionConfig ReducedStream SkeletonSection OutputSkeleton defaultConfig windowLines dedupLines reduceLines reduceStream reduceText truncateSummary generateSpoolPath extractErrorSummary demuxStream extractOutputSkeleton skeletonHasErrors? formatOutputSkeleton] :i [(ansi :a ansi) (diagnostics :a diag) (asl-proc/coreProcess :a proc)])

(schema ReductionConfig (:f headLimit Int64) (:f tailLimit Int64) (:f dedupRepeats Bool))

(schema ReducedStream (:f rawLineCount Int64) (:f reducedLineCount Int64) (:f evictedLineCount Int64) (:f lines (List String)) (:f text String) (:f diagnostics diag/DiagnosticSummary))

(schema SkeletonSection (:f title String) (:f startLine Int64) (:f endLine Int64) (:f lineCount Int64) (:f hasError Bool))

(schema OutputSkeleton (:f totalLines Int64) (:f totalBytes Int64) (:f sections (List SkeletonSection)) (:f diagnostics (List diag/Diagnostic)) (:f summary String))

(schema SectionBuilderState (:f currentTitle String) (:f startLine Int64) (:f currentLine Int64) (:f hasErr Bool) (:f completed (List SkeletonSection)))

fn defaultConfig -> ReductionConfig
  (ReductionConfig :headLimit 500 :tailLimit 1500 :dedupRepeats true)

fn windowLines lines: (List String) headLimit: Int64 tailLimit: Int64 -> (Pair (List String) Int64)
  (let [(total (listLength lines)) (capacity (+ headLimit tailLimit))] (if (<= total capacity) (pair lines 0) (let [(evicted (- total capacity)) (marker (str "... [" (stringFromInt64 evicted) " lines evicted from buffer] ...")) (headPart (if (> headLimit 0) (optionOr (listSlice lines 0 headLimit) (list)) (list))) (tailStart (- total tailLimit)) (tailPart (if (> tailLimit 0) (optionOr (listSlice lines tailStart total) (list)) (list))) (combined (listAppend headPart (cons marker tailPart)))] (pair combined evicted))))

(schema DedupState (:f prevLine String) (:f repeatCount Int64) (:f acc (List String)))

fn dedupStep st: DedupState line: String -> DedupState
  (let [(prev st.prevLine) (count st.repeatCount) (acc st.acc)] (if (= line prev) (DedupState :prevLine prev :repeatCount (+ count 1) :acc acc) (let [(withMarker (if (> count 1) (let [(marker (str "  ... [repeated " (stringFromInt64 (- count 1)) " more times] ..."))] (cons marker acc)) acc))] (DedupState :prevLine line :repeatCount 1 :acc (cons line withMarker)))))

fn dedupLines lines: (List String) -> (List String)
  (let [(n (listLength lines))] (if (<= n 1) lines (let [(firstLine (optionOr (listHead lines) "")) (restLines (optionOr (listTail lines) (list))) (init (DedupState :prevLine firstLine :repeatCount 1 :acc (list firstLine))) (fin (fold dedupStep init restLines)) (finalAcc (if (> fin.repeatCount 1) (let [(m (str "  ... [repeated " (stringFromInt64 (- fin.repeatCount 1)) " more times] ..."))] (cons m fin.acc)) fin.acc))] (listReverse finalAcc))))

fn reduceLines lines: (List String) cfg: ReductionConfig -> (Pair (List String) Int64)
  (let [(deduped (if cfg.dedupRepeats (dedupLines lines) lines))] (windowLines deduped cfg.headLimit cfg.tailLimit))

fn reduceStream rawText: String cfg: ReductionConfig -> ReducedStream
  (let [(cleaned (ansi/cleanTerminalText rawText)) (lines (stringSplit cleaned "\n")) (rawCount (listLength lines)) (diags (diag/extractDiagnostics lines)) (summary (diag/summarizeDiagnostics diags)) (windowRes (reduceLines lines cfg)) (finalLines (pairFirst windowRes)) (evictedCount (pairSecond windowRes)) (reducedCount (listLength finalLines)) (finalText (stringJoin finalLines "\n"))] (ReducedStream :rawLineCount rawCount :reducedLineCount reducedCount :evictedLineCount evictedCount :lines finalLines :text finalText :diagnostics summary))

fn reduceText rawText: String -> ReducedStream
  (reduceStream rawText (defaultConfig))

fn truncateSummary text: String maxTokens: Int64 -> String
  (let [(maxChars (* maxTokens 4)) (len (stringLength text))] (if (<= len maxChars) text (let [(sliceLen (if (> maxChars 3) (- maxChars 3) maxChars)) (prefix (optionOr (stringSlice text 0 sliceLen) text))] (str prefix "..."))))

fn generateSpoolPath bin: String nonce: Int64 baseDir: String -> String
  (let [(safeBin (stringReplace bin "/" "_"))] (str baseDir "/asl-proc-" safeBin "-" (stringFromInt64 nonce) ".spool"))

fn extractErrorSummary stdoutText: String stderrText: String exitCode: Int64 -> String
  (if (= exitCode 0) "Command succeeded" (let [(errCleaned (ansi/cleanTerminalText stderrText)) (outCleaned (ansi/cleanTerminalText stdoutText)) (errLines (if (stringEmpty? errCleaned) (list) (stringSplit errCleaned "\n"))) (outLines (if (stringEmpty? outCleaned) (list) (stringSplit outCleaned "\n"))) (diags (diag/extractDiagnostics (listAppend errLines outLines)))] (if (> (listLength diags) 0) (let [(firstDiag (optionOr (listHead diags) (diag/Diagnostic :kind "error" :severity "error" :message "Process failed" :file "" :line 0 :col 0 :raw (list)))) (msg firstDiag.message) (loc (if (not (stringEmpty? firstDiag.file)) (str firstDiag.file ":" (stringFromInt64 firstDiag.line) ": ") "")) (diagStr (str loc msg))] (truncateSummary diagStr 50)) (let [(combined (if (not (stringEmpty? (stringTrim errCleaned))) errCleaned outCleaned))] (if (stringEmpty? (stringTrim combined)) (str "Process failed with exit code " (stringFromInt64 exitCode)) (let [(firstLine (optionOr (listHead (stringSplit combined "\n")) "Process failed")) (trimmedLine (stringTrim firstLine))] (if (stringEmpty? trimmedLine) (str "Process failed with exit code " (stringFromInt64 exitCode)) (truncateSummary trimmedLine 50))))))))

fn demuxStream stdoutText: String stderrText: String exitCode: Int64 durationMs: Int64 spoolPath: String -> proc/ProcessReceipt
  (let [(summary (extractErrorSummary stdoutText stderrText exitCode))] (proc/makeProcessReceipt exitCode durationMs 0 spoolPath summary))

fn isSectionHeader? line: String -> Bool
  (let [(t (stringTrim line))] (or (stringStartsWith? t "--> ") (or (stringStartsWith? t "=== ") (or (stringStartsWith? t "--- ") (or (stringStartsWith? t "### ") (or (stringStartsWith? t "## ") (or (stringStartsWith? t "[Phase ") (or (stringStartsWith? t "[Step ") (or (stringStartsWith? t "Step ") (or (stringStartsWith? t "Phase ") (or (stringStartsWith? t "Test suite ") (or (stringStartsWith? t "[Config]") (stringStartsWith? t "================================================================================")))))))))))))

fn isErrorLine? line: String -> Bool
  (let [(lower (stringLower line))] (or (stringContains? lower "error") (or (stringContains? lower "failed") (or (stringContains? lower "fatal") (stringContains? lower "panic")))))

fn stepSection st: SectionBuilderState line: String -> SectionBuilderState
  (let [(nextIdx (+ st.currentLine 1))] (if (isSectionHeader? line) (let [(completedSec (SkeletonSection :title st.currentTitle :startLine st.startLine :endLine st.currentLine :lineCount (+ (- st.currentLine st.startLine) 1) :hasError st.hasErr)) (title (truncateSummary (stringTrim line) 40))] (SectionBuilderState :currentTitle title :startLine nextIdx :currentLine nextIdx :hasErr (isErrorLine? line) :completed (cons completedSec st.completed))) (with st :currentLine nextIdx :hasErr (or st.hasErr (isErrorLine? line)))))

fn partitionSections lines: (List String) -> (List SkeletonSection)
  (if (listEmpty? lines) (list) (let [(firstLine (optionOr (listHead lines) "")) (firstTitle (if (isSectionHeader? firstLine) (truncateSummary (stringTrim firstLine) 40) "Initial Output")) (initSt (SectionBuilderState :currentTitle firstTitle :startLine 1 :currentLine 1 :hasErr (isErrorLine? firstLine) :completed (list))) (restLines (optionOr (listTail lines) (list))) (fin (fold stepSection initSt restLines)) (finalSec (SkeletonSection :title fin.currentTitle :startLine fin.startLine :endLine fin.currentLine :lineCount (+ (- fin.currentLine fin.startLine) 1) :hasError fin.hasErr))] (listReverse (cons finalSec fin.completed))))

fn buildSkeletonSummary totalLines: Int64 secCount: Int64 diags: (List diag/Diagnostic) -> String
  (let [(diagCount (listLength diags))] (if (= diagCount 0) (str "Lines: " (stringFromInt64 totalLines) " | Sections: " (stringFromInt64 secCount) " | Status: clean") (let [(firstD (optionOr (listHead diags) (diag/Diagnostic :kind "" :severity "" :message "error" :file "" :line 0 :col 0 :raw (list)))) (loc (if (stringEmpty? firstD.file) "" (str firstD.file ":" (stringFromInt64 firstD.line) " ")))] (str "Lines: " (stringFromInt64 totalLines) " | Sections: " (stringFromInt64 secCount) " | Errors: " (stringFromInt64 diagCount) " (" loc (truncateSummary firstD.message 20) ")"))))

fn extractOutputSkeleton rawText: String -> OutputSkeleton
  (if (stringEmpty? (stringTrim rawText)) (OutputSkeleton :totalLines 0 :totalBytes 0 :sections (list) :diagnostics (list) :summary "Lines: 0 | Sections: 0 | Status: clean") (let [(cleaned (ansi/cleanTerminalText rawText)) (norm (stringReplace cleaned "\r\n" "\n")) (trimmed (if (stringEndsWith? norm "\n") (optionOr (stringSlice norm 0 (- (stringLength norm) 1)) norm) norm)) (lines (stringSplit trimmed "\n")) (totalLines (listLength lines)) (totalBytes (stringLength norm)) (diags (diag/extractDiagnostics lines)) (sections (partitionSections lines)) (summary (buildSkeletonSummary totalLines (listLength sections) diags))] (OutputSkeleton :totalLines totalLines :totalBytes totalBytes :sections sections :diagnostics diags :summary summary)))

fn skeletonHasErrors? skel: OutputSkeleton -> Bool
  (or (> (listLength skel.diagnostics) 0) (fold (fn [(acc Bool) (s SkeletonSection)] -> Bool (or acc s.hasError)) false skel.sections))

fn formatOutputSkeleton skel: OutputSkeleton -> String
  (let [(header (str "=== Output Skeleton (" (stringFromInt64 skel.totalLines) " lines, " (stringFromInt64 skel.totalBytes) " bytes) ===\n")) (secRows (map (fn [(s SkeletonSection)] -> String (let [(errTag (if s.hasError " [FAIL]" " [OK]"))] (str "  L" (stringFromInt64 s.startLine) "-L" (stringFromInt64 s.endLine) " (" (stringFromInt64 s.lineCount) " lines)" errTag " " s.title))) skel.sections)) (body (stringJoin secRows "\n")) (summaryLine (str "\nSummary: " skel.summary))] (str header body summaryLine))
