(module asl-ui/tests/sds1ThemeTest :x [runTests] :i [(asl-ui/tokens :a tokens) (asl-ui/theme :a theme)])

fn testGridScale -> Bool
  (let [(g1 (tokens/gridStep 1)) (g2 (tokens/gridStep 2)) (g3 (tokens/gridStep 3)) (g4 (tokens/gridStep 4)) (g6 (tokens/gridStep 6)) (g8 (tokens/gridStep 8)) (v8 (tokens/isValidGridStep? 8)) (v16 (tokens/isValidGridStep? 16)) (v7 (tokens/isValidGridStep? 7))] (assert (= g1 4) "Grid step 1 is 4px") (assert (= g2 8) "Grid step 2 is 8px") (assert (= g3 12) "Grid step 3 is 12px") (assert (= g4 16) "Grid step 4 is 16px") (assert (= g6 24) "Grid step 6 is 24px") (assert (= g8 32) "Grid step 8 is 32px") (assert v8 "8px is valid grid step") (assert v16 "16px is valid grid step") (refute v7 "7px must be rejected by grid validator") true)

fn testTypographyTokens -> Bool
  (let [(tMicro (tokens/getTypographyToken "micro")) (tCode (tokens/getTypographyToken "code")) (tDisplay (tokens/getTypographyToken "display"))] (assert (= tMicro.fontSize 10) "Micro font size is 10px") (assert tCode.isMono "Code token is monospace") (assert (not tMicro.isMono) "Micro token is not monospace") (assert (= tDisplay.fontSize 28) "Display font size is 28px") (refute tDisplay.isMono "Display token must not be mono") true)

fn testSds1DarkThemeAndContrast -> Bool
  (let [(t (theme/sds1DarkTheme)) (valRes (theme/validateSds1ThemeContrast t)) (cueOk (theme/formatStatusBadgeWithCue "verified")) (cueFail (theme/formatStatusBadgeWithCue "defect")) (cueVac (theme/formatStatusBadgeWithCue "vacuousMock")) (cueCpl (theme/formatStatusBadgeWithCue "coupling"))] (assert (ok? valRes) "SDS-1 dark theme passes strict WCAG AAA contrast verification") (assert (= cueOk "[OK] Verified") "Verified cue matches format") (assert (= cueFail "[FAIL] Defect") "Defect cue matches format") (assert (= cueVac "[VACUOUS] Hollow Mock") "Vacuous mock cue matches format") (assert (= cueCpl "[CYCLE] High Coupling") "Coupling cue matches format") (refute (= t.bgBase.hex "#ffffff") "SDS-1 dark theme canvas is not white") true)

fn runTests -> Bool
  (let [(okG (testGridScale)) (okT (testTypographyTokens)) (okTh (testSds1DarkThemeAndContrast))] (and (and okG okT) okTh))
