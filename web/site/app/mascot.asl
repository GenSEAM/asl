(module aslSite/app/mascot
  :x [tailMark leon iconSvg easterBackdrop]
  :i [(asl-html/html :a h)])

fn tailPath -> String
  "M 78 82 C 83 72 84 48 81 32 C 77 16 64 8 46 8 C 26 8 13 19 8 36 C 4 52 7 72 18 84 C 28 94 44 95 56 88 C 64 82 68 70 67 58 C 66 44 57 35 44 35 C 32 35 25 44 25 54 C 25 62 31 67 38 67 C 43 67 46 63 46 58 C 46 53 41 52 38 55 C 36 57 34 55 34 52 C 34 46 40 41 46 41 C 53 41 57 48 57 57 C 57 67 50 75 42 76 C 31 77 21 70 17 60 C 14 48 16 36 24 26 C 33 16 46 15 56 19 C 66 24 70 35 70 50 L 70 82 C 70 86 77 86 78 82 Z"

fn tailDefs gradId: String -> h/Node
  (h/el "defs" []
    [(h/el "linearGradient" [(h/id gradId) (h/attr "x1" "15%") (h/attr "y1" "10%") (h/attr "x2" "85%") (h/attr "y2" "90%")]
       [(h/el "stop" [(h/attr "offset" "0%") (h/attr "stop-color" "#ffb8d9")] [])
        (h/el "stop" [(h/attr "offset" "45%") (h/attr "stop-color" "#ff5aa8")] [])
        (h/el "stop" [(h/attr "offset" "100%") (h/attr "stop-color" "#c2185b")] [])])])

fn tailLogoSvg clsName: String gradId: String -> h/Node
  (h/svg [(h/cls clsName) (h/attr "viewBox" "0 0 100 100") (h/attr "aria-hidden" "true") (h/attr "focusable" "false")]
    [(tailDefs gradId)
     (h/path [(h/cls "tail-mark") (h/attr "d" (tailPath)) (h/attr "fill" (str "url(#" gradId ")")) (h/attr "stroke" "#ff8ec4") (h/attr "stroke-width" "1.2") (h/attr "stroke-linejoin" "round")])])

fn tailMark size: String -> h/Node
  (tailLogoSvg (str "cham " size) "tailGrad")

fn lid cx: String cy: String rx: String ry: String -> h/Node
  (h/ellipse [(h/cls "leon-lid") (h/attr "cx" cx) (h/attr "cy" cy) (h/attr "rx" rx) (h/attr "ry" ry)])

fn leon -> h/Node
  (h/div [(h/cls "leon")]
    [(h/div [(h/cls "leon-swing")]
      [(h/img [(h/cls "leon-art") (h/src "/leon.webp") (h/alt "Leon the chameleon, the AgentSlang mascot") (h/attr "width" "640") (h/attr "height" "640")])
       (h/svg [(h/cls "leon-lids") (h/attr "viewBox" "0 0 1024 1024") (h/attr "aria-hidden" "true") (h/attr "focusable" "false")]
         [(lid "574" "305" "80" "84")
          (lid "811" "300" "33" "78")
          (h/path [(h/cls "leon-lash") (h/attr "d" "M 512 338 Q 574 392 636 338")])
          (h/path [(h/cls "leon-lash") (h/attr "d" "M 786 330 Q 811 372 836 330")])])])])

fn cyberLeaf tx: String ty: String rot: String -> h/Node
  (h/g [(h/cls "vine-leaf") (h/attr "transform" (str "translate(" tx "," ty ") rotate(" rot ")" ))]
    [(h/path [(h/attr "d" "M 0 0 Q 13 -8 26 0 Q 13 8 0 0")])
     (h/line [(h/attr "x1" "0") (h/attr "y1" "0") (h/attr "x2" "26") (h/attr "y2" "0")])])

fn leftVineNodes -> (List h/Node)
  [(h/path [(h/cls "vine-trunk") (h/attr "d" "M 8 -40 C 14 40 20 120 16 189 C 12 300 4 420 10 560 C 16 700 6 860 10 1000")])
   (h/path [(h/cls "vine-dash") (h/attr "d" "M 14 -40 C 20 40 26 120 22 189 C 18 300 10 420 16 560 C 22 700 12 860 16 1000")])
   (cyberLeaf "15" "270" "24")
   (cyberLeaf "8" "430" "-28")
   (cyberLeaf "12" "620" "22")
   (cyberLeaf "9" "820" "-25")]

fn eggGroup side: String y: String x: String rot: String shapes: (List h/Node) -> h/Node
  (h/g [(h/cls "egg-item") (h/attr "data-egg" side) (h/attr "data-y" y) (h/attr "data-x" x) (h/attr "data-r" rot) (h/attr "transform" (str "translate(" x "," y ") rotate(" rot ")" ))]
    shapes)

fn leftCycle offset: Int64 -> (List h/Node)
  [(eggGroup "L" (stringFromInt64 (+ offset 480)) "122" "36"
     [(h/circle [(h/attr "cx" "0") (h/attr "cy" "0") (h/attr "r" "11")])
      (h/path [(h/cls "egg-dash") (h/attr "d" "M-9 -6A11 11 0 0 0 9 -6")])
      (h/path [(h/attr "d" "M-7 -7L-38 -24M-9 2L-42 12M8 -6L36 -26M9 3L38 14")])])
   (eggGroup "L" (stringFromInt64 (+ offset 740)) "54" "-18"
     [(h/path [(h/attr "d" "M0 -24L18 -8L10 18L-10 18L-18 -8Z")])
      (h/path [(h/attr "d" "M-10 18L0 26L10 18M-6 -19L-12 -28M6 -19L12 -28")])
      (h/path [(h/cls "egg-dash") (h/attr "d" "M-18 -8L0 4L18 -8M0 -24L0 26")])])
   (eggGroup "L" (stringFromInt64 (+ offset 1000)) "118" "15"
     [(h/rect [(h/attr "x" "-32") (h/attr "y" "-13") (h/attr "width" "64") (h/attr "height" "26") (h/attr "rx" "2")])
      (h/circle [(h/attr "cx" "-14") (h/attr "cy" "-2") (h/attr "r" "5")])
      (h/circle [(h/attr "cx" "14") (h/attr "cy" "-2") (h/attr "r" "5")])
      (h/path [(h/attr "d" "M-20 13L-15 7L15 7L20 13")])
      (h/path [(h/cls "egg-dash") (h/attr "d" "M-6 -2L6 -2")])])
   (eggGroup "L" (stringFromInt64 (+ offset 1260)) "58" "-32"
     [(h/path [(h/attr "d" "M-12 -18L12 -18L6 0L-6 0Z")])
      (h/path [(h/attr "d" "M-6 0L6 0L18 18L-18 18Z")])
      (h/path [(h/cls "egg-dash") (h/attr "d" "M0 -18L0 18M-18 18L-24 26M18 18L24 26M0 18L0 28")])])
   (eggGroup "L" (stringFromInt64 (+ offset 1520)) "128" "26"
     [(h/path [(h/attr "d" "M-18 -20L12 -20L20 -12L20 20L-18 20Z")])
      (h/rect [(h/attr "x" "-10") (h/attr "y" "-20") (h/attr "width" "18") (h/attr "height" "11")])
      (h/rect [(h/attr "x" "-12") (h/attr "y" "4") (h/attr "width" "24") (h/attr "height" "16")])
      (h/circle [(h/cls "egg-dash") (h/attr "cx" "0") (h/attr "cy" "-2") (h/attr "r" "4")])])
   (eggGroup "L" (stringFromInt64 (+ offset 1780)) "56" "22"
     [(h/path [(h/attr "d" "M-13 6L-13 -8A13 13 0 0 1 13 -8L13 6Z")])
      (h/path [(h/attr "d" "M-17 6L17 6M-7 -4L7 -4M0 -10L0 2M-8 6L-8 22M0 6L0 26M8 6L8 22")])
      (h/circle [(h/cls "egg-dash") (h/attr "cx" "0") (h/attr "cy" "-4") (h/attr "r" "8")])])]

fn leftEggs -> (List h/Node)
  (listAppend
    (leftVineNodes)
    (cons
      (h/path [(h/cls "egg-arc") (h/attr "d" "M 125 480 C 110 370 55 260 -80 160")])
      (listAppend (leftCycle 0) (leftCycle 1560))))

fn rightCycle offset: Int64 -> (List h/Node)
  [(eggGroup "R" (stringFromInt64 (+ offset 180)) "118" "16"
     [(h/path [(h/attr "d" "M-10 -16L10 -16L16 -6L12 8L-12 8L-16 -6Z")])
      (h/rect [(h/attr "x" "-14") (h/attr "y" "8") (h/attr "width" "28") (h/attr "height" "8")])
      (h/path [(h/attr "d" "M-12 16L-24 28M-28 28L-18 28M12 16L24 28M18 28L28 28M-5 16L-8 24L8 24L5 16")])
      (h/circle [(h/cls "egg-dash") (h/attr "cx" "0") (h/attr "cy" "-5") (h/attr "r" "5")])])
   (eggGroup "R" (stringFromInt64 (+ offset 440)) "56" "-26"
     [(h/path [(h/attr "d" "M14 4C14 14 2 20 -8 16C-18 12 -22 -2 -16 -12C-10 -20 4 -22 12 -14C18 -8 16 4 8 8C2 10 -4 6 -4 0C-4 -4 0 -6 3 -4")])
      (h/path [(h/cls "egg-dash") (h/attr "d" "M14 4L4 -2M8 15L2 4M-6 16L-2 5M-16 6L-4 1M-15 -10L-3 -2M-2 -19L1 -4")])])
   (eggGroup "R" (stringFromInt64 (+ offset 700)) "122" "32"
     [(h/circle [(h/attr "cx" "0") (h/attr "cy" "-14") (h/attr "r" "4")])
      (h/circle [(h/attr "cx" "-12") (h/attr "cy" "10") (h/attr "r" "4")])
      (h/circle [(h/attr "cx" "0") (h/attr "cy" "2") (h/attr "r" "4")])
      (h/circle [(h/attr "cx" "12") (h/attr "cy" "-6") (h/attr "r" "4")])
      (h/circle [(h/attr "cx" "12") (h/attr "cy" "10") (h/attr "r" "4")])
      (h/circle [(h/attr "cx" "-12") (h/attr "cy" "-6") (h/attr "r" "4")])
      (h/path [(h/cls "egg-dash") (h/attr "d" "M-18 -18L18 -18L18 18L-18 18Z")])])
   (eggGroup "R" (stringFromInt64 (+ offset 960)) "64" "-18"
     [(h/path [(h/attr "d" "M-14 -10C-12 -19 -2 -22 6 -16C14 -20 22 -12 20 -2C20 8 10 14 2 12L-16 12C-22 12 -24 4 -18 0C-22 -4 -20 -10 -14 -10Z")])
      (h/path [(h/attr "d" "M2 4C6 -2 14 -2 16 4M11 1L13 1")])
      (h/path [(h/cls "egg-dash") (h/attr "d" "M-14 4C-8 0 -4 8 2 4")])])
   (eggGroup "R" (stringFromInt64 (+ offset 1220)) "116" "22"
     [(h/circle [(h/attr "cx" "0") (h/attr "cy" "-10") (h/attr "r" "6")])
      (h/path [(h/attr "d" "M0 -4L0 18M-7 0L7 0M0 18C-10 18 -16 11 -16 3M0 18C10 18 16 11 16 3M-16 3L-12 7M16 3L12 7")])
      (h/path [(h/cls "egg-dash") (h/attr "d" "M-16 3C-22 -4 -14 -16 0 -16")])])
   (eggGroup "R" (stringFromInt64 (+ offset 1480)) "54" "-28"
     [(h/rect [(h/attr "x" "-14") (h/attr "y" "-20") (h/attr "width" "28") (h/attr "height" "40") (h/attr "rx" "2")])
      (h/path [(h/attr "d" "M-5 -20A5 5 0 0 0 5 -20M-22 -12L-14 -12M-22 -4L-14 -4M-22 4L-14 4M-22 12L-14 12M14 -12L22 -12M14 -4L22 -4M14 4L22 4M14 12L22 12")])
      (h/rect [(h/cls "egg-dash") (h/attr "x" "-6") (h/attr "y" "-8") (h/attr "width" "12") (h/attr "height" "16")])])]

fn rightEggs -> (List h/Node)
  (listAppend (rightCycle 0) (rightCycle 1560))

fn easterBackdrop -> h/Node
  (h/div [(h/cls "cosmic-bg") (h/id "easter-layer") (h/attr "aria-hidden" "true")]
    [(h/a [(h/href "/") (h/cls "chameleon-perch") (h/id "chameleon-perch") (h/attr "title" "AgentSlang · Leon the chameleon")]
       [(leon)])
     (h/svg [(h/cls "easter-stream left") (h/attr "viewBox" "0 0 180 1000") (h/attr "preserveAspectRatio" "xMinYMin slice") (h/attr "fill" "none")] (leftEggs))
     (h/svg [(h/cls "easter-stream right") (h/attr "viewBox" "0 0 180 1000") (h/attr "preserveAspectRatio" "xMinYMin slice") (h/attr "fill" "none")] (rightEggs))])

fn iconSvg -> h/Node
  (tailLogoSvg "cham small" "favTailGrad")
