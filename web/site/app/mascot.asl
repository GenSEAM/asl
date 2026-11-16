(module aslSite/app/mascot
  :x [tailMark leon dock iconSvg easterBackdrop]
  :i [(asl-html/html :a h)])

fn svgText attrs: (List h/Attr) s: String -> h/Node
  (h/el "text" attrs [(h/text s)])

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

fn tailSections -> String
  "156,586,62;157,610,62;158,635,62;162,659,63;166,684,64;172,708,64;178,732,64;189,759,62;200,786,59;221,807,55;242,828,51;268,839,48;293,850,45;317,855,42;342,861,39;398,862,36;430,849,35;455,829,34;472,805,33;480,779,32;481,754,30;475,731,29;471,712,29;463,694,28;450,680,28;434,669,27;417,663,27;398,662,26;380,663,26;363,669,26;347,680,26;334,694,26;326,712,26;322,731,25;326,751,26;335,768,26;348,782,26;364,792,27;381,797,27;398,798,27;414,790,26;425,778,24;432,765,22;435,752,21;433,741,19;428,731,18;426,724,17;423,717,17;418,712,17;412,708,17;405,706,17;398,706,17;391,705,16;384,706,16;377,710,15;370,715,15;365,723,14;362,731,14;365,741,13;369,748,12;375,755,12;383,759,11;391,761,10;398,761,10;405,757,9;410,752,8;414,747,8;415,741,7;414,736,7;412,731,6;410,728,5;408,726,5;405,725,4;402,725,4;400,725,3"

fn leon -> h/Node
  (h/div [(h/cls "leon")]
    [(h/div [(h/cls "leon-swing")]
      [(h/img [(h/cls "leon-art") (h/src "/leon.webp") (h/alt "Leon the chameleon, the AgentSlang mascot") (h/attr "width" "640") (h/attr "height" "640")])
       (h/svg [(h/cls "leon-lids") (h/attr "viewBox" "0 0 1024 1024") (h/attr "aria-hidden" "true") (h/attr "focusable" "false")]
         [(lid "574" "305" "80" "84")
          (lid "811" "300" "33" "78")
          (h/path [(h/cls "leon-lash") (h/attr "d" "M 512 338 Q 574 392 636 338")])
          (h/path [(h/cls "leon-lash") (h/attr "d" "M 786 330 Q 811 372 836 330")])])])
     (h/el "canvas" [(h/cls "leon-rig") (h/id "leon-rig") (h/attr "aria-hidden" "true") (h/attr "data-body" "/leon-body.webp") (h/attr "data-art" "/leon.webp") (h/attr "data-tail" (tailSections))] [])])

fn dock dockId: String label: String -> h/Node
  (h/div [(h/cls "leon-dock") (h/id dockId)] [(h/span [(h/cls "micro")] [(h/text label)])])

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

fn eggGroup side: String y: String x: String rot: String label: String shapes: (List h/Node) -> h/Node
  (h/g [(h/cls "egg-item") (h/attr "data-egg" side) (h/attr "data-y" y) (h/attr "data-x" x) (h/attr "data-r" rot) (h/attr "transform" (str "translate(" x "," y ") rotate(" rot ")" ))]
    (listAppend shapes [(svgText [(h/cls "egg-txt") (h/attr "x" "-18") (h/attr "y" "34")] label)]))

fn leftCycle offset: Int64 -> (List h/Node)
  [(eggGroup "L" (stringFromInt64 (+ offset 480)) "122" "36" "PS-01 · Ø16"
     [(h/circle [(h/attr "cx" "0") (h/attr "cy" "0") (h/attr "r" "10")])
      (h/path [(h/attr "d" "M-7 -7L-44 -26M-7 7L-48 20M7 -7L38 -32M7 7L42 26")])])
   (eggGroup "L" (stringFromInt64 (+ offset 740)) "54" "-18" "V-12 · CHK"
     [(h/path [(h/attr "d" "M-14 24L-14 -4C-14 -18 14 -18 14 -4L14 24Z")])
      (h/path [(h/cls "egg-dash") (h/attr "d" "M-8 4L8 4M-8 12L8 12M-6 24L-6 32M6 24L6 32")])])
   (eggGroup "L" (stringFromInt64 (+ offset 1000)) "118" "15" "ASN · 10110"
     [(h/rect [(h/attr "x" "-44") (h/attr "y" "-10") (h/attr "width" "88") (h/attr "height" "20") (h/attr "rx" "2")])
      (h/path [(h/attr "d" "M-22 -10L-22 10M0 -10L0 10M22 -10L22 10M0 -18L0 -10")])])
   (eggGroup "L" (stringFromInt64 (+ offset 1260)) "58" "-32" "F=26mm · OPT"
     [(h/circle [(h/cls "egg-dash") (h/attr "cx" "0") (h/attr "cy" "0") (h/attr "r" "28")])
      (h/path [(h/attr "d" "M-22 -6A24 24 0 0 1 22 -6ZM0 -22L0 -34")])])
   (eggGroup "L" (stringFromInt64 (+ offset 1520)) "128" "26" "ROM-144 · CAD"
     [(h/rect [(h/attr "x" "-22") (h/attr "y" "-24") (h/attr "width" "44") (h/attr "height" "48") (h/attr "rx" "2")])
      (h/circle [(h/cls "egg-dash") (h/attr "cx" "0") (h/attr "cy" "6") (h/attr "r" "10")])])
   (eggGroup "L" (stringFromInt64 (+ offset 1780)) "56" "22" "2N3904 · GATE"
     [(h/path [(h/attr "d" "M-14 0A14 14 0 0 1 14 0ZM-8 0L-8 24M0 0L0 28M8 0L8 24")])])]

fn leftEggs -> (List h/Node)
  (listAppend
    (leftVineNodes)
    (listAppend
      [(h/path [(h/cls "egg-arc") (h/attr "d" "M 125 480 C 110 370 55 260 -80 160")])
       (svgText [(h/cls "egg-txt") (h/attr "x" "16") (h/attr "y" "268") (h/attr "transform" "rotate(-36 16 268)")] "<< DIVERSION-ARC <<")]
      (listAppend (leftCycle 0) (leftCycle 1560))))

fn rightCycle offset: Int64 -> (List h/Node)
  [(eggGroup "R" (stringFromInt64 (+ offset 180)) "118" "16" "TRANQ-11"
     [(h/path [(h/attr "d" "M-12 -14L12 -14L18 -6L18 10L12 16L-12 16L-18 10L-18 -6Z")])
      (h/path [(h/attr "d" "M-14 14L-26 28M14 14L26 28M-8 16L-10 24L10 24L8 16")])])
   (eggGroup "R" (stringFromInt64 (+ offset 440)) "56" "-26" "AST · G2"
     [(h/circle [(h/attr "cx" "0") (h/attr "cy" "0") (h/attr "r" "21")])
      (h/circle [(h/cls "egg-dash") (h/attr "cx" "0") (h/attr "cy" "0") (h/attr "r" "11")])
      (h/path [(h/attr "d" "M0 0L-16 -9M0 0L15 -11M0 0L-6 17M0 0L13 15")])])
   (eggGroup "R" (stringFromInt64 (+ offset 700)) "122" "32" "L2-HEX"
     [(h/path [(h/attr "d" "M0 -18L10 -12L10 0L0 6L-10 0L-10 -12ZM10 0L20 6L20 18L10 24L0 18L0 6ZM-10 0L0 6L0 18L-10 24L-20 18L-20 6Z")])])
   (eggGroup "R" (stringFromInt64 (+ offset 960)) "64" "-18" "WASM-32 · IR"
     [(h/rect [(h/attr "x" "-32") (h/attr "y" "-18") (h/attr "width" "64") (h/attr "height" "36") (h/attr "rx" "2")])
      (h/path [(h/attr "d" "M-24 -6L-14 -6L-14 -12L-4 -12L-4 -6L8 -6L8 -12L18 -12L18 -6L24 -6")])])
   (eggGroup "R" (stringFromInt64 (+ offset 1220)) "116" "22" "ASN · WIRE"
     [(h/path [(h/attr "d" "M-24 14L26 14M-24 14L-24 -16M-24 -10C-8 -8 2 6 24 10")])
      (h/circle [(h/attr "cx" "24") (h/attr "cy" "10") (h/attr "r" "3")])])
   (eggGroup "R" (stringFromInt64 (+ offset 1480)) "54" "-28" "NE555 · CLK"
     [(h/rect [(h/attr "x" "-16") (h/attr "y" "-22") (h/attr "width" "32") (h/attr "height" "44") (h/attr "rx" "2")])
      (h/path [(h/attr "d" "M-24 -12L-16 -12M-24 0L-16 0M-24 12L-16 12M16 -12L24 -12M16 0L24 0M16 12L24 12")])])]

fn rightEggs -> (List h/Node)
  (listAppend (rightCycle 0) (rightCycle 1560))

fn easterBackdrop -> h/Node
  (h/div [(h/cls "cosmic-bg") (h/id "easter-layer") (h/attr "aria-hidden" "true")]
    [(h/a [(h/href "/") (h/cls "chameleon-perch") (h/id "chameleon-perch") (h/attr "title" "AgentSlang · Leon the chameleon")]
       [(leon)])
     (h/svg [(h/cls "easter-stream left") (h/attr "viewBox" "0 0 180 1000") (h/attr "preserveAspectRatio" "xMinYMin slice") (h/attr "fill" "none")] (leftEggs))
     (h/svg [(h/cls "easter-stream right") (h/attr "viewBox" "0 0 180 1000") (h/attr "preserveAspectRatio" "xMinYMin slice") (h/attr "fill" "none")] (rightEggs))])

fn iconSvg -> h/Node
  (h/svg [(h/attr "xmlns" "http://www.w3.org/2000/svg") (h/attr "viewBox" "0 0 100 100") (h/attr "fill" "none")]
    [(tailDefs "favTailGrad")
     (h/rect [(h/attr "width" "100") (h/attr "height" "100") (h/attr "rx" "18") (h/attr "fill" "#0f0b10")])
     (h/path [(h/attr "d" (tailPath)) (h/attr "fill" "url(#favTailGrad)") (h/attr "stroke" "#ff8ec4") (h/attr "stroke-width" "1.2") (h/attr "stroke-linejoin" "round")])])
