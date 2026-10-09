(module asl-proc/ansi :x [stripAnsi collapseCrSegment collapseCrLine collapseCr cleanTerminalText])

(schema AnsiState (:f state Int64) (:f acc (List String)))

fn ansiStep st: AnsiState ch: String -> AnsiState
  (let [(s st.state) (acc st.acc)] (cond ((= s 0) (if (= ch "\u001b") (AnsiState :state 1 :acc acc) (AnsiState :state 0 :acc (cons ch acc)))) ((= s 1) (cond ((= ch "[") (AnsiState :state 2 :acc acc)) ((= ch "]") (AnsiState :state 3 :acc acc)) ((or (= ch "(") (= ch ")")) (AnsiState :state 4 :acc acc)) ((or (= ch "N") (= ch "O")) (AnsiState :state 4 :acc acc)) ((= ch "\u001b") (AnsiState :state 1 :acc acc)) (else (AnsiState :state 0 :acc acc)))) ((= s 2) (cond ((and (>= ch "@") (<= ch "~")) (AnsiState :state 0 :acc acc)) ((= ch "\u001b") (AnsiState :state 1 :acc acc)) (else st))) ((= s 3) (cond ((or (= ch "\u0007") (= ch "\u0000")) (AnsiState :state 0 :acc acc)) ((= ch "\u001b") (AnsiState :state 5 :acc acc)) (else st))) ((= s 4) (AnsiState :state 0 :acc acc)) ((= s 5) (cond ((= ch "\\") (AnsiState :state 0 :acc acc)) ((= ch "[") (AnsiState :state 2 :acc acc)) (else (AnsiState :state 0 :acc acc)))) (else (AnsiState :state 0 :acc (cons ch acc)))))

fn stripAnsi s: String -> String
  (if (not (stringContains? s "\u001b")) s (let [(init (AnsiState :state 0 :acc (list))) (fin (fold ansiStep init (stringChars s)))] (stringJoin (listReverse fin.acc) "")))

fn collapseCrSegment prev: String curr: String -> String
  (let [(lPrev (stringLength prev)) (lCurr (stringLength curr))] (if (>= lCurr lPrev) curr (let [(tail (optionOr (stringSlice prev lCurr lPrev) ""))] (str curr tail))))

fn collapseCrLine line: String -> String
  (if (not (stringContains? line "\r")) line (let [(segments (stringSplit line "\r"))] (fold collapseCrSegment "" segments)))

fn collapseCr text: String -> String
  (let [(norm (stringReplace text "\r\n" "\n"))] (if (not (stringContains? norm "\r")) norm (let [(lines (stringSplit norm "\n")) (collapsed (map collapseCrLine lines))] (stringJoin collapsed "\n"))))

fn cleanTerminalText text: String -> String
  (collapseCr (stripAnsi text))
