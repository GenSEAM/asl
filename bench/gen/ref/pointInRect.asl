schema Point { x: Int64 y: Int64 }

schema Rect { left: Int64 top: Int64 width: Int64 height: Int64 }

fn pointInRect p: Point r: Rect -> Bool
  (and (and (>= p.x r.left) (<= p.x (+ r.left r.width)))
       (and (>= p.y r.top) (<= p.y (+ r.top r.height))))
