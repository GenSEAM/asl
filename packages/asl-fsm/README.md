# @genseam/fsm (ASL Algebraic State Machine)

Mathematically verified finite state machine engine with exhaustive pattern matching and effect isolation.

## Installation
```bash
asl get github.com/GenSEAM/fsm
```

## Key Invariants
- **Exhaustive Matching:** Statically verified against ASL Rule 9 (0 unhandled state transitions).
- **Effect Isolation:** Pure transition logic with host side-effects isolated by `!` markers.

## License
MIT
