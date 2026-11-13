enum Command (go direction: String) (pick item: String) (look) (quit)

fn parseCommand line: String -> (Result Command String)
  (let [(words (stringSplit line " "))
        (verb (optionOr (listHead words) ""))
        (arg (optionOr (listGet words 1) ""))
        (two (and (= (listLength words) 2) (not (stringEmpty? arg))))]
    (cond
      ((= line "look") (ok (look)))
      ((= line "quit") (ok (quit)))
      ((and two (and (= verb "go") (listContains? (list "north" "south" "east" "west") arg))) (ok (go arg)))
      ((and two (= verb "pick")) (ok (pick arg)))
      (else (err (str "unknown command: " line)))))
