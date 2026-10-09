(module asl-ui/terminalCanvas :x [TerminalCell makeTerminalCell defaultCell TerminalBuffer makeTerminalBuffer getCell setCell fillBox drawBorder drawText TerminalCanvas makeTerminalCanvas swapBuffers renderAnsiDiff cellKey isCellEqual?] :i [])

(schema TerminalCell (:f ch String) (:f fg String) (:f bg String) (:f bold Bool) (:f underline Bool))

(schema TerminalBuffer (:f width Int64) (:f height Int64) (:f cells (Map String TerminalCell)))

(schema TerminalCanvas (:f width Int64) (:f height Int64) (:f frontBuffer TerminalBuffer) (:f backBuffer TerminalBuffer))

fn cellKey x: Int64 y: Int64 -> String
  (str (stringFromInt64 x) "," (stringFromInt64 y))

fn makeTerminalCell ch: String fg: String bg: String bold: Bool underline: Bool -> TerminalCell
  (TerminalCell :ch ch :fg fg :bg bg :bold bold :underline underline)

fn defaultCell -> TerminalCell
  (TerminalCell :ch " " :fg "default" :bg "default" :bold false :underline false)

fn isCellEqual? a: TerminalCell b: TerminalCell -> Bool
  (and (= a.ch b.ch) (and (= a.fg b.fg) (and (= a.bg b.bg) (and (= a.bold b.bold) (= a.underline b.underline)))))

fn makeTerminalBuffer width: Int64 height: Int64 -> TerminalBuffer
  (let [(w (if (<= width 0) 80 width))
        (h (if (<= height 0) 24 height))]
    (TerminalBuffer :width w :height h :cells (mapEmpty)))

fn getCell buf: TerminalBuffer x: Int64 y: Int64 -> TerminalCell
  (if (or (or (< x 0) (>= x buf.width)) (or (< y 0) (>= y buf.height)))
    (defaultCell)
    (optionOr (mapGet buf.cells (cellKey x y)) (defaultCell)))

fn setCell buf: TerminalBuffer x: Int64 y: Int64 cell: TerminalCell -> TerminalBuffer
  (if (or (or (< x 0) (>= x buf.width)) (or (< y 0) (>= y buf.height)))
    buf
    (with buf :cells (mapSet buf.cells (cellKey x y) cell)))

fn fillRowLoop buf: TerminalBuffer currX: Int64 endX: Int64 y: Int64 cell: TerminalCell -> TerminalBuffer
  (if (>= currX endX)
    buf
    (fillRowLoop (setCell buf currX y cell) (+ currX 1) endX y cell))

fn fillBoxLoop buf: TerminalBuffer x: Int64 endX: Int64 currY: Int64 endY: Int64 cell: TerminalCell -> TerminalBuffer
  (if (>= currY endY)
    buf
    (let [(rowBuf (fillRowLoop buf x endX currY cell))]
      (fillBoxLoop rowBuf x endX (+ currY 1) endY cell)))

fn fillBox buf: TerminalBuffer x: Int64 y: Int64 w: Int64 h: Int64 ch: String fg: String bg: String -> TerminalBuffer
  (let [(cell (makeTerminalCell ch fg bg false false))]
    (fillBoxLoop buf x (+ x w) y (+ y h) cell))

fn drawTextLoop buf: TerminalBuffer currX: Int64 y: Int64 text: String idx: Int64 len: Int64 cell: TerminalCell -> TerminalBuffer
  (if (>= idx len)
    buf
    (let [(ch (optionOr (stringSlice text idx (+ idx 1)) ""))
          (nextCell (with cell :ch ch))]
      (drawTextLoop (setCell buf currX y nextCell) (+ currX 1) y text (+ idx 1) len cell)))

fn drawText buf: TerminalBuffer x: Int64 y: Int64 text: String fg: String bg: String bold: Bool -> TerminalBuffer
  (let [(cell (makeTerminalCell "" fg bg bold false))
        (len (stringLength text))]
    (drawTextLoop buf x y text 0 len cell))

fn fillColLoop buf: TerminalBuffer leftX: Int64 rightX: Int64 currY: Int64 endY: Int64 cell: TerminalCell -> TerminalBuffer
  (if (>= currY endY)
    buf
    (let [(bLeft (setCell buf leftX currY cell))
          (bBoth (setCell bLeft rightX currY cell))]
      (fillColLoop bBoth leftX rightX (+ currY 1) endY cell)))

fn drawBorder buf: TerminalBuffer x: Int64 y: Int64 w: Int64 h: Int64 title: String style: String fg: String bg: String -> TerminalBuffer
  (if (or (<= w 1) (<= h 1))
    buf
    (let [(cTL (if (= style "double") "╔" (if (= style "rounded") "╭" "┌")))
          (cTR (if (= style "double") "╗" (if (= style "rounded") "╮" "┐")))
          (cBL (if (= style "double") "╚" (if (= style "rounded") "╰" "└")))
          (cBR (if (= style "double") "╝" (if (= style "rounded") "╯" "┘")))
          (cH (if (= style "double") "═" "─"))
          (cV (if (= style "double") "║" "│"))
          (cellH (makeTerminalCell cH fg bg false false))
          (cellV (makeTerminalCell cV fg bg false false))
          (buf1 (fillRowLoop buf (+ x 1) (+ x (- w 1)) y cellH))
          (buf2 (fillRowLoop buf1 (+ x 1) (+ x (- w 1)) (+ y (- h 1)) cellH))
          (buf3 (fillColLoop buf2 x (+ x (- w 1)) (+ y 1) (+ y (- h 1)) cellV))
          (buf4 (setCell buf3 x y (makeTerminalCell cTL fg bg false false)))
          (buf5 (setCell buf4 (+ x (- w 1)) y (makeTerminalCell cTR fg bg false false)))
          (buf6 (setCell buf5 x (+ y (- h 1)) (makeTerminalCell cBL fg bg false false)))
          (buf7 (setCell buf6 (+ x (- w 1)) (+ y (- h 1)) (makeTerminalCell cBR fg bg false false)))]
      (if (stringEmpty? title)
        buf7
        (let [(safeTitle (str " " title " "))]
          (drawText buf7 (+ x 2) y safeTitle fg bg true)))))

fn makeTerminalCanvas width: Int64 height: Int64 -> TerminalCanvas
  (let [(w (if (<= width 0) 80 width))
        (h (if (<= height 0) 24 height))]
    (TerminalCanvas :width w :height h :frontBuffer (makeTerminalBuffer w h) :backBuffer (makeTerminalBuffer w h)))

fn swapBuffers canvas: TerminalCanvas -> TerminalCanvas
  (with canvas :frontBuffer canvas.backBuffer :backBuffer (makeTerminalBuffer canvas.width canvas.height))

fn ansiColorCode fg: String -> String
  (if (= fg "green") "\x1b[32m"
    (if (= fg "red") "\x1b[31m"
      (if (= fg "yellow") "\x1b[33m"
        (if (= fg "blue") "\x1b[34m"
          (if (= fg "magenta") "\x1b[35m"
            (if (= fg "cyan") "\x1b[36m"
              (if (= fg "white") "\x1b[37m"
                "\x1b[39m")))))))

fn renderRowDiff front: TerminalBuffer back: TerminalBuffer y: Int64 currX: Int64 width: Int64 acc: String -> String
  (if (>= currX width)
    acc
    (let [(cFront (getCell front currX y))
          (cBack (getCell back currX y))]
      (if (isCellEqual? cFront cBack)
        (renderRowDiff front back y (+ currX 1) width acc)
        (let [(pos (str "\x1b[" (stringFromInt64 (+ y 1)) ";" (stringFromInt64 (+ currX 1)) "H"))
              (col (ansiColorCode cBack.fg))
              (boldSeq (if cBack.bold "\x1b[1m" ""))
              (cellStr (str pos col boldSeq cBack.ch "\x1b[0m"))
              (nextAcc (str acc cellStr))]
          (renderRowDiff front back y (+ currX 1) width nextAcc)))))

fn renderDiffLoop front: TerminalBuffer back: TerminalBuffer currY: Int64 height: Int64 width: Int64 acc: String -> String
  (if (>= currY height)
    acc
    (let [(rowStr (renderRowDiff front back currY 0 width ""))
          (nextAcc (str acc rowStr))]
      (renderDiffLoop front back (+ currY 1) height width nextAcc)))

fn renderAnsiDiff canvas: TerminalCanvas -> String
  (renderDiffLoop canvas.frontBuffer canvas.backBuffer 0 canvas.height canvas.width "")
