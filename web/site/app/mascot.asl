(module aslSite/app/mascot
  :x [chameleon iconSvg]
  :i [(aslSite/ui/html :a h)])

fn stroke d: String -> h/Node
  (h/path [(h/attr "d" d)])

fn part kind: String d: String -> h/Node
  (h/path [(h/cls kind) (h/attr "d" d)])

fn dot cx: String cy: String r: String kind: String -> h/Node
  (h/circle [(h/cls kind) (h/attr "cx" cx) (h/attr "cy" cy) (h/attr "r" r)])

fn outline -> (List h/Node)
  [(stroke "M76 22C56 18 36 28 32 48C30 60 32 70 35 78C39 92 32 104 19 103C6 102 3 86 12 80C21 74 33 80 31 90C29 97 19 97 18 90C17 85 23 83 25 87")
   (stroke "M76 22C80 14 88 10 94 12C104 16 110 28 111 40C106 47 98 50 90 50")
   (stroke "M90 50C86 58 78 62 68 63C56 64 44 62 33 57")
   (stroke "M111 40C105 41 99 41 94 40")
   (stroke "M78 61C80 66 82 70 84 73M79 75C82 72 87 72 90 75")
   (stroke "M48 63C47 66 47 70 50 73M45 75C48 72 52 72 55 75")
   (dot "95" "29" "7" "eye")
   (dot "96" "29" "3.2" "iris")
   (dot "96.5" "29" "1.2" "pupil")]

fn chameleon detailed: Bool size: String -> h/Node
  (h/svg [(h/cls (str "cham " size)) (h/attr "viewBox" "0 0 120 108") (h/attr "aria-hidden" "true") (h/attr "focusable" "false")]
    (if detailed
      (cons (part "branch" "M2 75C36 71 84 71 118 75") (cons (part "band" "M50 24C55 34 56 48 52 60M64 21C69 32 70 48 66 62") (outline)))
      (cons (part "branch" "M2 75C36 71 84 71 118 75") (outline))))

fn iconSvg -> h/Node
  (h/svg [(h/attr "viewBox" "0 0 120 108") (h/attr "fill" "none") (h/attr "stroke" "#ff5aa8") (h/attr "stroke-width" "7") (h/attr "stroke-linecap" "round") (h/attr "stroke-linejoin" "round")]
    (listAppend (listTake (outline) 6)
      [(h/circle [(h/attr "cx" "95") (h/attr "cy" "29") (h/attr "r" "8") (h/attr "fill" "#121012")])
       (h/circle [(h/attr "cx" "96") (h/attr "cy" "29") (h/attr "r" "2.4") (h/attr "fill" "#ff5aa8") (h/attr "stroke" "none")])]))
