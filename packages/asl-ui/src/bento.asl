(module asl-ui/bento :x [BentoTile makeBentoTile BentoGrid makeBentoGrid isTileDirty? reconcileBentoTile calculateBentoTileBounds renderBentoGrid] :i [(asl-ui/vnode :a ui) (asl-ui/tokens :a tokens) (asl-ui/layout :a layout)])

(schema BentoTile (:f id String) (:f colSpan Int64) (:f rowSpan Int64) (:f structuralHash Int64) (:f content ui/VNode) (:f isDirty Bool))

(schema BentoGrid (:f id String) (:f columns Int64) (:f gap Int64) (:f tiles (List BentoTile)))

fn makeBentoTile id: String colSpan: Int64 rowSpan: Int64 structuralHash: Int64 content: ui/VNode -> BentoTile
  (let [(safeCol (if (<= colSpan 0) 1 (if (> colSpan 12) 12 colSpan))) (safeRow (if (<= rowSpan 0) 1 (if (> rowSpan 6) 6 rowSpan)))] (BentoTile :id id :colSpan safeCol :rowSpan safeRow :structuralHash structuralHash :content content :isDirty true))

fn makeBentoGrid id: String gap: Int64 tiles: (List BentoTile) -> BentoGrid
  (let [(safeGap (if (tokens/isValidGridStep? gap) gap 16))] (BentoGrid :id id :columns 12 :gap safeGap :tiles tiles))

fn isTileDirty? oldTile: BentoTile newTile: BentoTile -> Bool
  (not (= oldTile.structuralHash newTile.structuralHash))

fn reconcileBentoTile oldTile: BentoTile newTile: BentoTile -> BentoTile
  (if (isTileDirty? oldTile newTile) newTile (with oldTile :isDirty false))

fn calculateBentoTileBounds tile: BentoTile baseColWidth: Int64 baseRowHeight: Int64 gap: Int64 -> layout/Dimensions
  (let [(cSpan tile.colSpan) (rSpan tile.rowSpan) (w (+ (* cSpan baseColWidth) (* (- cSpan 1) gap))) (h (+ (* rSpan baseRowHeight) (* (- rSpan 1) gap)))] (layout/makeDimensions w h))

fn renderTileVNode tile: BentoTile -> ui/VNode
  (let [(attrs (mapSet (mapSet (mapSet (mapEmpty) "class" "sds1-bento-tile") "data-tile-id" tile.id) "data-col-span" (stringFromInt64 tile.colSpan)))] (ui/makeContainer (str "tile-" tile.id) attrs (list tile.content)))

fn renderBentoGrid grid: BentoGrid -> ui/VNode
  (let [(tileNodes (fold (fn [(acc (List ui/VNode)) (t BentoTile)] -> (List ui/VNode) (listAppend acc (list (renderTileVNode t)))) (list) grid.tiles)) (gridAttrs (mapSet (mapSet (mapSet (mapEmpty) "class" "sds1-bento-grid") "data-grid-id" grid.id) "gap" (stringFromInt64 grid.gap)))] (ui/makeContainer (str "grid-" grid.id) gridAttrs tileNodes))
