(module aslBrowserPlugin/plugin :x [startPlugin getPluginVersion getAslanyBrand] :i [(aslBrowserPlugin/runtime :a rt) (aslBrowserPlugin/safetyGate :a sg) (aslBrowserPlugin/localSlm :a slm) (aslBrowserPlugin/meshClient :a mc) (aslBrowserPlugin/domCompiler :a dc)])

fn getPluginVersion -> Str
  "1.0.0"

fn getAslanyBrand -> Str
  "Aslany"

fn startPlugin -> Str
  "Aslany Browser Plugin initialized with AudioWorklet 16kHz and CDP bridge."
