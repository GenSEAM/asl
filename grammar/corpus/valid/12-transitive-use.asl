"Transitivity: this module calls through an intermediary that speaks in a third"

"module's type, and never imports that third module. Naming the type would"

"require the import — corpus/valid/09 is the fixture that does."

(module text/consume :x [show] :i [(text/report :a r)])

fn show -> String
  (r/describe (r/unitSquare))
