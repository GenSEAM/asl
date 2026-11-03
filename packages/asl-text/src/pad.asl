(module asl-text/pad
  :x [padStart padEnd center truncate]
  :i [])

fn codePointCount s: String -> Int64
  (listLength (stringChars s))

fn codePointSlice s: String start: Int64 end: Int64 -> String
  (stringJoin (optionOr (listSlice (stringChars s) start end) (list)) "")

fn padStart s: String width: Int64 fill: String -> String
  (let [(len (codePointCount s))]
    (if (>= len width) s
      (let [(padNeeded (- width len))
            (padding (codePointSlice (stringRepeat fill padNeeded) 0 padNeeded))]
        (str padding s))))

fn padEnd s: String width: Int64 fill: String -> String
  (let [(len (codePointCount s))]
    (if (>= len width) s
      (let [(padNeeded (- width len))
            (padding (codePointSlice (stringRepeat fill padNeeded) 0 padNeeded))]
        (str s padding))))

fn center s: String width: Int64 fill: String -> String
  (let [(len (codePointCount s))]
    (if (>= len width) s
      (let [(pad (- width len))
            (left (/ pad 2))
            (right (- pad left))
            (leftPad (codePointSlice (stringRepeat fill left) 0 left))
            (rightPad (codePointSlice (stringRepeat fill right) 0 right))]
        (str leftPad s rightPad))))

fn truncate s: String width: Int64 marker: String -> String
  (let [(len (codePointCount s))
        (mLen (codePointCount marker))]
    (if (<= len width) s
      (if (<= mLen width)
        (str (codePointSlice s 0 (- width mLen)) marker)
        (codePointSlice marker 0 width))))