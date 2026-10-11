(module asl-checker/fixtures/withForm :x [Point update])

schema Point {
  x: Int64
  y: Int64
}

fn update p: Point -> Point
  (with p :x 42)
