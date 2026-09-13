(module aslWeb/graphShowcase
  :d "Declarative Graph Reactor Showcase View in ASL"
  :x [describeGraphShowcase]
  :i [(asl-text/string :a s)])

(df describeGraphShowcase [] -> Str
  :d "Returns structured description of the 1M node graph showcase"
  "(showcase :title \"AgentScript High-Scale Graph Reactor\" :nodes 1000000 :tiers [\"javascript\" \"webassembly\" \"webgpu\"])")
