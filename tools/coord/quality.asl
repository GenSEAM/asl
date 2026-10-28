(module asl-tools/coord/quality
  :x [Cell Lie Ranked qualityOf spreadPermille rankPlace]
  :i [])

(schema Cell
  (:f alias String)
  (:f place String)
  (:f passes Int64)
  (:f total Int64))

(schema Lie
  (:f alias String)
  (:f place String))

(schema Ranked
  (:f alias String)
  (:f place String)
  (:f quality Int64)
  (:f total Int64)
  (:f class Int64))

fn liePenalty -> Int64
  50

fn qualityOf passes: Int64 total: Int64 lies: Int64 -> Int64
  (if (<= total 0) 0 (max 0 (- (/ (* passes 1000) total) (* lies (liePenalty)))))

fn liesFor alias: String place: String lies: (List Lie) -> Int64
  (listLength (filter (fn [(x Lie)] -> Bool (and (= x.alias alias) (= x.place place))) lies))

fn rankedOf c: Cell lies: (List Lie) -> Ranked
  (Ranked :alias c.alias :place c.place :quality (qualityOf c.passes c.total (liesFor c.alias c.place lies)) :total c.total :class 0)

fn spreadPermille spreadPasses: Int64 total: Int64 -> Int64
  (if (<= total 0) 1000 (/ (* spreadPasses 1000) total))

fn withClass r: Ranked cls: Int64 -> Ranked
  (Ranked :alias r.alias :place r.place :quality r.quality :total r.total :class cls)

fn classify spreadPasses: Int64 sorted: (List Ranked) -> (List Ranked)
  (fold (fn [(acc (List Ranked)) (r Ranked)] -> (List Ranked)
          (match (listHead (listReverse acc))
            ((none) (list (withClass r 1)))
            ((some last)
              (let [(top (optionOr (listHead (filter (fn [(x Ranked)] -> Bool (= x.class last.class)) acc)) last))
                    (within (<= (- top.quality r.quality) (spreadPermille spreadPasses top.total)))]
                (listAppend acc (list (withClass r (if within last.class (+ last.class 1)))))))))
        (list) sorted)

fn rankPlace place: String cells: (List Cell) lies: (List Lie) spreadPasses: Int64 -> (List Ranked)
  (let [(mine (filter (fn [(c Cell)] -> Bool (= c.place place)) cells))
        (byAlias (listSortBy (fn [(r Ranked)] -> String r.alias) (map (fn [(c Cell)] -> Ranked (rankedOf c lies)) mine)))]
    (classify spreadPasses (listSortBy (fn [(r Ranked)] -> Int64 (- 0 r.quality)) byAlias)))
