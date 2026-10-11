(module text/consume :x [show] :i [(text/report :a r)])

fn show -> String
  (r/describe (r/unitSquare))
