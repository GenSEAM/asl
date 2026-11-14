(module asl-ui/tests/semTokensTest
  :x [runTests]
  :i [(asl-ui/semTokens :a t)])

fn units l: t/Length -> Int64
  (match l ((t/dp n) n))

fn rising? values: (List Int64) -> Bool
  (listAll? (fn [p] (< (pairFirst p) (pairSecond p))) (zip values (listDrop values 1)))

fn near? x: Float64 want: Float64 -> Bool
  (< (abs (- x want)) 0.01)

fn runTests -> Bool
  (let [(theme (t/defaultTheme))
        (spaces (map (fn [s] (units (t/spaceOf theme s))) (t/allSpaces)))
        (on (fn [role] (t/contrast (t/colorOf theme role) (t/colorOf theme (t/surface)))))]
    (assert (= spaces [4 8 16 24 40]) "each space step resolves to its own theme length, in scale order")
    (assert (= (units theme.stroke) 1) "the stroke is one unit wide")
    (assert (rising? spaces) "the space scale rises from xs to xl")
    (assert (= (map (fn [r] (units (t/radiusOf theme r))) (t/allRadii)) [0 6 999]) "each radius resolves to its own theme length")
    (assert (= (map (fn [r] (units (t/textOf theme r).size)) (t/allTextRoles)) [16 13 14 20 28 14]) "each text role resolves to its own size")
    (assert (listAll? (fn [r] (> (units (t/textOf theme r).line) (units (t/textOf theme r).size))) (t/allTextRoles)) "line height exceeds font size for every text role")
    (assert (= (map (fn [r] (t/textOf theme r).fixedPitch) (t/allTextRoles)) [false false false false false true]) "only the mono role is fixed pitch")
    (assert (= (map (fn [r] (t/textOf theme r).weight) (t/allTextRoles)) [400 400 600 600 700 400]) "each text role resolves to its own weight")
    (assert (= (t/colorOf theme (t/fill (t/primary))) (t/rgb 11 87 208)) "fill of a tone is the tone's fill colour")
    (assert (= (t/colorOf theme (t/onFill (t/primary))) (t/rgb 255 255 255)) "onFill of a tone is the tone's content colour")
    (assert (= (t/colorOf theme (t/fill (t/danger))) (t/rgb 179 38 30)) "the danger tone resolves to its own fill")
    (assert (= (t/colorOf theme (t/inkWeak)) (t/rgb 89 89 89)) "weak ink resolves to its own colour")
    (assert (= (t/colorOf theme (t/selection)) (t/rgb 207 224 255)) "selection resolves to its own colour")
    (assert (near? (t/contrast (t/rgb 0 0 0) (t/rgb 255 255 255)) 21.0) "black on white has the WCAG contrast 21")
    (assert (near? (t/contrast (t/rgb 255 255 255) (t/rgb 0 0 0)) 21.0) "contrast does not depend on argument order")
    (assert (near? (t/contrast (t/rgb 119 119 119) (t/rgb 255 255 255)) 4.48) "mid grey on white has the WCAG contrast 4.48")
    (assert (near? (t/luminance (t/rgb 0 255 0)) 0.7152) "green carries the WCAG luminance share")
    (assert (listAll? (fn [tone] (>= (t/contrast (t/colorOf theme (t/fill tone)) (t/colorOf theme (t/onFill tone))) 4.5)) (t/allTones)) "content on every tone fill meets WCAG AA")
    (assert (>= (on (t/ink)) 7.0) "ink on the surface meets WCAG AAA")
    (assert (>= (on (t/inkWeak)) 4.5) "weak ink on the surface meets WCAG AA")
    (assert (>= (on (t/linkInk)) 4.5) "link ink on the surface meets WCAG AA")
    (assert (>= (on (t/border)) 3.0) "the border meets the WCAG non-text contrast")
    (assert (>= (on (t/focusRing)) 3.0) "the focus ring meets the WCAG non-text contrast")
    (assert (>= (t/contrast (t/colorOf theme (t/ink)) (t/colorOf theme (t/selection))) 4.5) "ink on a selection meets WCAG AA")
    (assert (= (map t/spaceName (t/allSpaces)) ["xs" "sm" "md" "lg" "xl"]) "space names follow the scale")
    (assert (= (map t/toneName (t/allTones)) ["neutral" "primary" "success" "warn" "danger"]) "tone names are distinct")
    (assert (= (map t/textName (t/allTextRoles)) ["body" "caption" "label" "title" "display" "mono"]) "text role names are distinct")
    (assert (= (map t/radiusName (t/allRadii)) ["sharp" "soft" "pill"]) "radius names are distinct")
    (assert (= (map t/emphasisName [(t/strong) (t/normal) (t/weak)]) ["strong" "normal" "weak"]) "emphasis names are distinct")
    true)
