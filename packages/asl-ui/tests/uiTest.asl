(module asl-ui/tests/uiTest
  :d "Unit test suite for pure ASL declarative UI DSL, Elm runtime, frame arena, layout engine, and theme system"
  :x [RunTests runTests]
  :i [(asl-ui/vnode :a ui)
      (asl-ui/runtime :a elm)
      (asl-ui/arena :a arena)
      (asl-ui/layout :a layout)
      (asl-ui/tokens :a tokens)
      (asl-ui/theme :a theme)
      (asl-ui/ax :a ax)
      (asl-ui/query :a query)
      (asl-ui/renderWeb :a web)
      (asl-ui/renderNative :a native)])

(df testVNodeAndElmRuntime [] -> Bool
  :d "Verifies VNode primitives, key validation, and Elm runtime state stepping"
  (let [(btn (ui/makeButton "btn-submit" (map-empty) (list (ui/makeText "Click" "lbl-1"))))
        (validKeys (ui/validateKeyUniqueness btn))
        (initModel (elm/makeCounterModel 10 "count: 10"))
        (incMsg (elm/makeMsg "increment" 5))
        (stepRes (elm/stepRuntime initModel incMsg))
        (nextModel (.-model stepRes))
        (viewTree (elm/renderCounterView nextModel))]
    (assert (= (.-tag btn) "button") "Button tag is button")
    (assert (= (.-key btn) "btn-submit") "Button key is btn-submit")
    (assert (is-ok? validKeys) "Valid unique keys pass validation")
    (assert (= (.-count nextModel) 15) "Increment message updates counter to 15")
    (assert (= (.-tag viewTree) "container") "Counter view renders container root")
    (refute (= (.-count nextModel) 10) "Refutation: State must advance from initial count")
    true))

(df testFrameArenaAllocation [] -> Bool
  :d "Verifies frame arena ping-pong swapping and capacity overflow checks"
  (let [(fArena (arena/makeFrameArena 1024))
        (alloc1 (arena/allocFrameNode fArena "btn-1" "button" 64))
        (swapped (arena/swapArenas fArena))
        (smallArena (arena/makeFrameArena 64))
        (overflowAlloc (arena/tryAllocFrameNode smallArena "huge-node" "container" 2048))]
    (assert (= (.-activeIdx fArena) 0) "Initial arena active index is 0")
    (assert (is-ok? alloc1) "Valid allocation succeeds")
    (assert (= (.-activeIdx swapped) 1) "Swapped arena active index is 1")
    (assert (is-err? overflowAlloc) "Allocation exceeding capacity returns error")
    (assert (= (unwrap-err overflowAlloc) "ERR_ARENA_OVERFLOW") "Error code is ERR_ARENA_OVERFLOW")
    (refute (= (.-activeIdx swapped) 0) "Refutation: Active index must change on arena swap")
    (refute (is-ok? overflowAlloc) "Refutation: Overflow allocation must never succeed")
    true))

(df testLayoutEngine [] -> Bool
  :d "Verifies two-pass constraint layout measure and arrange"
  (let [(c (layout/makeConstraints 50 400 30 300))
        (txt (ui/makeVNode "text" "t1" "Hello" (map-empty) (list) 80 20 true))
        (dim (layout/measure txt c))
        (box (layout/arrange txt (layout/makeRect 0 0 (.-width dim) (.-height dim))))]
    (assert (= (.-width dim) 80) "Intrinsic text width 80 within bounds")
    (assert (= (.-height dim) 30) "Intrinsic text height 20 clamped to minHeight 30")
    (assert (= (.-x (.-bounds box)) 0) "Arranged box x is 0")
    (assert (= (.-y (.-bounds box)) 0) "Arranged box y is 0")
    (refute (< (.-height dim) 30) "Refutation: Height must not drop below min constraint")
    true))

(df testTokensAndTheme [] -> Bool
  :d "Verifies grid steps, typography tokens, and WCAG contrast ratio calculation"
  (let [(g1 (tokens/gridStep 1))
        (g2 (tokens/gridStep 2))
        (g4 (tokens/gridStep 4))
        (tBody (tokens/getTypographyToken "body"))
        (cWhite (theme/makeColorToken "white" "#ffffff" 255 255 255))
        (cBlack (theme/makeColorToken "black" "#000000" 0 0 0))
        (ratio (theme/calculateContrastRatio cWhite cBlack))
        (passAa (theme/verifyWcagAa cWhite cBlack))]
    (assert (= g1 4) "Grid step 1 is 4px")
    (assert (= g2 8) "Grid step 2 is 8px")
    (assert (= g4 16) "Grid step 4 is 16px")
    (assert (= (.-fontSize tBody) 14) "Body font size is 14px")
    (assert (= ratio 2100) "Black-on-white contrast ratio is 21.00:1 (2100)")
    (assert passAa "Black-on-white passes WCAG AA")
    (refute (< ratio 450) "Refutation: Black-on-white must exceed WCAG AA threshold")
    true))

(df testAccessibilityAndAgentQuery [] -> Bool
  :d "Verifies accessibility tree projection and symbolic agent query execution"
  (let [(btn (ui/makeButton "btn-ok" (map-empty) (list (ui/makeText "OK" "lbl-ok"))))
        (inp (ui/makeInput "inp-query" (map-empty)))
        (box (ui/makeContainer "c-main" (map-empty) (list btn inp)))
        (axRoot (ax/projectAccessibilityTree box))
        (qBtn (query/queryAxNodeByAnchor axRoot "btn-ok"))
        (allButtons (query/queryAllAxNodesByRole axRoot "button"))
        (rcpt (query/dispatchSemanticAction axRoot "click" "btn-ok" ""))
        (desc (query/describeAxNode axRoot))]
    (assert (= (.-role axRoot) "group") "Root container role is group")
    (assert (is-some? qBtn) "Query finds btn-ok anchor")
    (assert (= (.-role (option-or qBtn (ax/makeEmptyAXNode))) "button") "Button node role is button")
    (assert (= (list-length allButtons) 1) "Exactly 1 button found in query")
    (assert (= (.-status rcpt) "ok") "Click dispatch returns status ok")
    (assert (= (.-reason rcpt) "SUCCESS") "Click dispatch returns reason SUCCESS")
    (assert (> (string-length desc) 0) "AXNode description is non-empty")
    (refute (is-none? qBtn) "Refutation: Button anchor must exist")
    (refute (= (.-status rcpt) "error") "Refutation: Click on enabled button must not fail")
    true))

(df testWebAssemblyAndNativeSurfaceHost [] -> Bool
  :d "Verifies Web DOM mutation translation, HTML generation, native surface stride, and presentation"
  (let [(mInsert (arena/makeMutationRecord "insert" "btn-1" "button"))
        (patches (web/applyDomMutations (list mInsert)))
        (p (option-or (list-head patches) (web/makeEmptyDomPatch)))
        (vText (ui/makeText "Hello Native" "lbl-msg"))
        (vDiv (ui/makeContainer "c-box" (map-empty) (list vText)))
        (html (web/renderToHtml vDiv))
        (stride (native/calculateFrameStride 800 4))
        (surfRes (native/initNativeSurface "Native Host" 800 600))
        (h (option-or (result-to-option surfRes) -1))
        (buf (native/generateSolidFrameBuffer 800 600 0 255 0))
        (presentRes (native/presentNativeFrame h buf 4096))
        (vsyncOk (native/syncVSync 60))
        (unmapOk (native/verifyBufferUnmap h))]
    (assert (= (.-opcode p) "DOM_INSERT") "Mutation insert maps to DOM_INSERT")
    (assert (str-contains? html "Hello Native") "Rendered HTML contains inner text")
    (assert (= stride 3200) "Row stride for 800 width is 3200 bytes")
    (assert (> h 0) "Native surface initialization returns valid handle")
    (assert (is-ok? presentRes) "Native frame presentation succeeds")
    (assert vsyncOk "VSync synchronization returns true")
    (assert unmapOk "Buffer unmapping is verified")
    (refute (= (.-opcode p) "DOM_REMOVE") "Refutation: Insert mutation must not produce DOM_REMOVE")
    (refute (not vsyncOk) "Refutation: VSync must succeed")
    true))

(df runTests [] -> Bool
  :d "Runs all asl-ui unit test suites"
  (let [(okVnode (testVNodeAndElmRuntime))
        (okArena (testFrameArenaAllocation))
        (okLayout (testLayoutEngine))
        (okTheme (testTokensAndTheme))
        (okAx (testAccessibilityAndAgentQuery))
        (okHost (testWebAssemblyAndNativeSurfaceHost))]
    (and (and (and (and (and okVnode okArena) okLayout) okTheme) okAx) okHost)))

(df RunTests [] -> Bool
  :d "Export alias for runTests"
  (runTests))
