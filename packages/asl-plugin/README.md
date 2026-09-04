# @genseam/asl-plugin

Modular Plugin Architecture & Foreign Capability Interface for AgentScript Core.

## Overview

`asl-plugin` provides the formal decoupling layer between the pure AgentScript language core and external I/O / host capabilities:
- Database drivers (Postgres, SQLite, MySQL, ClickHouse)
- Operating system capabilities (Processes, POSIX signals, filesystem)
- Network transports (HTTP client, WebSocket, TCP)
- Browser automation & DevTools protocol adapters

By keeping all external system interfaces as modular plugins, AgentScript Core remains 100% self-hosted, lightweight, and embeddable inside any WebAssembly sandbox.

## Architecture

```
+-----------------------------------------------------------+
|               AgentScript Core Language Runtime            |
|       (Parser, Checker, Codegen, Core Builtins)           |
+-----------------------------------------------------------+
                              |
                     [asl-plugin Registry]
                              |
        +---------------------+---------------------+
        |                     |                     |
   [plugin-db]           [plugin-fs]           [plugin-net]
 (SQL execution)       (Host filesystem)     (Socket / HTTP)
```
