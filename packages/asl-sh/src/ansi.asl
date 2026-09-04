(module asl-sh/ansi
  :d "Pure ASL terminal emulation helpers: ANSI escape sequence stripping and carriage return collapsing."
  :x [strip-ansi collapse-cr-segment collapse-cr-line collapse-cr clean-terminal-text])

(dfs AnsiState
  (:f state Int64 "State machine state: 0=normal, 1=esc, 2=csi, 3=osc, 4=charset, 5=osc-esc")
  (:f acc (List String) "Reversed accumulated characters"))

(df ansi-step [(st AnsiState) (ch String)] -> AnsiState
  :d "Transitions the ANSI state machine for a single character."
  (let [(s (.-state st))
        (acc (.-acc st))]
    (cond
      ((= s 0)
       (if (= ch "\x1b")
           (AnsiState :state 1 :acc acc)
           (AnsiState :state 0 :acc (list-cons ch acc))))
      ((= s 1)
       (cond
         ((= ch "[") (AnsiState :state 2 :acc acc))
         ((= ch "]") (AnsiState :state 3 :acc acc))
         ((or (= ch "(") (= ch ")")) (AnsiState :state 4 :acc acc))
         ((or (= ch "N") (= ch "O")) (AnsiState :state 4 :acc acc))
         ((= ch "\x1b") (AnsiState :state 1 :acc acc))
         (:else (AnsiState :state 0 :acc acc))))
      ((= s 2)
       (cond
         ((and (>= ch "@") (<= ch "~")) (AnsiState :state 0 :acc acc))
         ((= ch "\x1b") (AnsiState :state 1 :acc acc))
         (:else st)))
      ((= s 3)
       (cond
         ((or (= ch "\x07") (= ch "\x00")) (AnsiState :state 0 :acc acc))
         ((= ch "\x1b") (AnsiState :state 5 :acc acc))
         (:else st)))
      ((= s 4)
       (AnsiState :state 0 :acc acc))
      ((= s 5)
       (cond
         ((= ch "\\") (AnsiState :state 0 :acc acc))
         ((= ch "[") (AnsiState :state 2 :acc acc))
         (:else (AnsiState :state 0 :acc acc))))
      (:else
       (AnsiState :state 0 :acc (list-cons ch acc))))))

(df strip-ansi [(s String)] -> String
  :d "Strips ANSI escape sequences from a string."
  (if (not (string-contains? s "\x1b"))
      s
      (let [(init (AnsiState :state 0 :acc (list)))
            (fin (fold ansi-step init (string-chars s)))]
        (string-join (list-reverse (.-acc fin)) ""))))

(df collapse-cr-segment [(prev String) (curr String)] -> String
  :d "Overwrites previous line content with current segment following carriage return."
  (let [(l-prev (string-length prev))
        (l-curr (string-length curr))]
    (if (>= l-curr l-prev)
        curr
        (let [(tail (option-or (string-slice prev l-curr l-prev) ""))]
          (str curr tail)))))

(df collapse-cr-line [(line String)] -> String
  :d "Collapses all carriage returns in a single line, simulating terminal overwriting."
  (if (not (string-contains? line "\r"))
      line
      (let [(segments (string-split line "\r"))]
        (fold collapse-cr-segment "" segments))))

(df collapse-cr [(text String)] -> String
  :d "Collapses terminal carriage returns across multiline text, normalizing CRLF to LF."
  (let [(norm (string-replace text "\r\n" "\n"))]
    (if (not (string-contains? norm "\r"))
        norm
        (let [(lines (string-split norm "\n"))
              (collapsed (map collapse-cr-line lines))]
          (string-join collapsed "\n")))))

(df clean-terminal-text [(text String)] -> String
  :d "Strips ANSI sequences and collapses carriage returns for clean terminal stream output."
  (collapse-cr (strip-ansi text)))
