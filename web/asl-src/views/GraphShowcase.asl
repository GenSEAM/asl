(module asl-web/graph-showcase
  :d "Declarative Graph Reactor Showcase View in ASL"
  :x [describe-graph-showcase]
  :i [(core/strings :a s)])

(df describe-graph-showcase [] -> Str
  :d "Returns structured description of the 1M node graph showcase"
  "(showcase :title \"AgentScript High-Scale Graph Reactor\" :nodes 1000000 :tiers [\"javascript\" \"webassembly\" \"webgpu\"])")
