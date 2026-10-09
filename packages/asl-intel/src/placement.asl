(module aslIntel/placement :x [auditFilePlacement] :i [])

fn auditFilePlacement filePath: Str content: Str -> Str
  (let [(lines (stringSplit content "\n")) (lineCount (listLength lines)) (cSym (stringContains? content ":sym")) (cNode (stringContains? content ":node")) (cRec (stringContains? content ":record")) (c-f (stringContains? content ":f ")) (hasRecords (or cSym (or cNode (or cRec c-f)))) (recLayout (if hasRecords "columnar" "aos")) (compactionScore (if hasRecords (if (> lineCount 100) 35.5 28.5) 0.0)) (savings (str (stringFromFloat64 compactionScore) "%"))] (str "(:placement-audit\n" "  :target \"" filePath "\"\n" "  :lines " (stringFromInt64 lineCount) "\n" "  :recommended-layout \"" recLayout "\"\n" "  :estimated-savings \"" savings "\"\n" "  :status \"analyzed\"\n" ")"))
