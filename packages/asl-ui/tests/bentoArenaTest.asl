(module asl-ui/tests/bentoArenaTest :x [runTests] :i [(asl-ui/vnode :a ui) (asl-ui/bento :a bento) (asl-ui/arena :a arena)])

fn testBentoTileAndGrid -> Bool
  (let [(c1 (ui/makeText "Radar Content" "lbl-radar")) (t1 (bento/makeBentoTile "radar" 4 4 1001 c1)) (t2 (bento/makeBentoTile "heatmap" 8 4 2002 (ui/makeText "Heatmap" "lbl-heat"))) (grid (bento/makeBentoGrid "cockpit-main" 16 (list t1 t2))) (dims (bento/calculateBentoTileBounds t1 80 60 16)) (vnode (bento/renderBentoGrid grid))] (assert (= t1.colSpan 4) "Radar colSpan is 4") (assert (= t1.rowSpan 4) "Radar rowSpan is 4") (assert (= grid.columns 12) "Grid columns is 12") (assert (= (listLength grid.tiles) 2) "Grid contains 2 tiles") (assert (= vnode.tag "container") "Rendered grid is container VNode") (assert (= dims.width (+ (* 4 80) (* 3 16))) "Calculated tile width matches formula") (refute (= t1.colSpan 12) "Radar must not take 12 columns") true)

fn testDirtySubtreeSkipping -> Bool
  (let [(c (ui/makeText "Static" "lbl-static")) (tOld (bento/makeBentoTile "t1" 4 4 500 c)) (tSame (bento/makeBentoTile "t1" 4 4 500 c)) (tNew (bento/makeBentoTile "t1" 4 4 501 (ui/makeText "Dynamic" "lbl-dyn"))) (isDirtySame (bento/isTileDirty? tOld tSame)) (isDirtyNew (bento/isTileDirty? tOld tNew)) (recSame (bento/reconcileBentoTile tOld tSame)) (recNew (bento/reconcileBentoTile tOld tNew))] (assert (not isDirtySame) "Unchanged structural hash is not dirty") (assert isDirtyNew "Changed structural hash is dirty") (assert (not recSame.isDirty) "Reconciled unchanged tile marked not dirty") (assert recNew.isDirty "Reconciled changed tile marked dirty") (refute isDirtySame "Identical hash must never be dirty") true)

fn testDoubleBufferedArenaSwap -> Bool
  (let [(pair (arena/makeFrameArenaPair 4096)) (swapped1 (arena/swapFrameArena pair)) (reset1 (arena/resetInactiveArena swapped1))] (assert pair.isAActive "Initially ArenaA is active") (assert (= pair.currentTick 0) "Initial tick is 0") (assert (not swapped1.isAActive) "After swap, ArenaB is active") (assert (= swapped1.currentTick 1) "After swap, tick is 1") (assert (= reset1.arenaA.capacityBytes 4096) "Reset arena maintains capacity") (refute swapped1.isAActive "Swapped arena must have A inactive") true)

fn runTests -> Bool
  (let [(okGrid (testBentoTileAndGrid)) (okSkip (testDirtySubtreeSkipping)) (okArena (testDoubleBufferedArenaSwap))] (and (and okGrid okSkip) okArena))
