(module asl-engine
  :x [resolveScope! checkSocketPath makeEngineRuntime dispatchRequest!
      cmdStatus! cmdPing! cmdStart! cmdStop! cmdRestart! cmdRun! cmdEval!]
  :i [(asl-engine/engine :a eng)])

fn resolveScope! rootDir: String scopeOpt: String -> eng/EngineConfig
  (eng/resolveScope! rootDir scopeOpt)

fn checkSocketPath socketPath: String isDarwin: Bool -> (Result Unit String)
  (eng/checkSocketPath socketPath isDarwin)

fn makeEngineRuntime config: eng/EngineConfig nowSec: Int64 -> eng/EngineRuntime
  (eng/makeEngineRuntime config nowSec)

fn dispatchRequest! rt: eng/EngineRuntime line: String nowSec: Int64 -> (Pair eng/EngineRuntime String)
  (eng/dispatchRequest! rt line nowSec)

fn cmdStatus! rootDir: String scopeOpt: String -> String
  (eng/cmdStatus! rootDir scopeOpt)

fn cmdPing! rootDir: String scopeOpt: String -> String
  (eng/cmdPing! rootDir scopeOpt)

fn cmdStart! rootDir: String scopeOpt: String foreground: Bool force: Bool -> (Result eng/EngineRuntime String)
  (eng/cmdStart! rootDir scopeOpt foreground force)

fn cmdStop! rootDir: String scopeOpt: String -> String
  (eng/cmdStop! rootDir scopeOpt)

fn cmdRestart! rootDir: String scopeOpt: String force: Bool -> (Result String String)
  (eng/cmdRestart! rootDir scopeOpt force)

fn cmdRun! rootDir: String scopeOpt: String -> (Result eng/EngineRuntime String)
  (eng/cmdRun! rootDir scopeOpt)

fn cmdEval! aslBin: String expr: String -> ProcessOutput
  (eng/cmdEval! aslBin expr)
