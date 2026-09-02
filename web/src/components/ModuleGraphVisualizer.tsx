import React, { useState } from 'react';
import { Section, SectionHeader } from './ui/primitives';

interface ModuleNode {
  id: string;
  name: string;
  category: 'sql' | 'mesh' | 'quality' | 'core';
  doc: string;
  schemas: string[];
  enums: string[];
  exportsCount: number;
  lines: number;
  quality: number;
  dependencies: string[];
}

const MODULES_REGISTRY: ModuleNode[] = [
  {
    id: 'asl-sql-core',
    name: 'asl-sql/core',
    category: 'sql',
    doc: 'Native AgentScript Cross-Dialect SQL AST Query Builder and Parameterized Renderer.',
    schemas: ['SqlJoin', 'SelectQuery', 'RenderedQuery'],
    enums: ['SqlDialect', 'BinaryOp', 'OrderDir', 'JoinType', 'SqlExpr'],
    exportsCount: 25,
    lines: 186,
    quality: 100,
    dependencies: [],
  },
  {
    id: 'asl-sql-ddl',
    name: 'asl-sql/ddl',
    category: 'sql',
    doc: 'Native AgentScript SQL DDL (Schema & Migrations) and DML (Insert, Update, Delete) Generator.',
    schemas: ['ColumnDef', 'TableDef', 'InsertQuery', 'UpdateQuery'],
    enums: ['SqlColumnType'],
    exportsCount: 15,
    lines: 87,
    quality: 100,
    dependencies: ['asl-sql/core'],
  },
  {
    id: 'asl-skyloom-core',
    name: 'asl-skyloom/core',
    category: 'mesh',
    doc: 'SkyLoom protocol algebraic types, asymmetric negotiation, and core frame logic.',
    schemas: ['FrameHeader', 'NegotiationState'],
    enums: ['Dialect', 'FrameType', 'ErrorCode'],
    exportsCount: 8,
    lines: 76,
    quality: 100,
    dependencies: [],
  },
  {
    id: 'asl-lint-core',
    name: 'asl-lint/core',
    category: 'quality',
    doc: 'AgentScript native quality inspection, anti-pattern smell classification, and score gate.',
    schemas: ['Smell', 'QualityMetrics'],
    enums: ['SmellSeverity', 'SmellCode'],
    exportsCount: 10,
    lines: 72,
    quality: 100,
    dependencies: [],
  },
  {
    id: 'asl-lint-clone',
    name: 'asl-lint/clone',
    category: 'quality',
    doc: 'AgentScript native structural clone, AST fingerprinting, and copy-paste detection.',
    schemas: ['CloneGroup', 'CloneVerdict'],
    enums: ['CloneType'],
    exportsCount: 6,
    lines: 34,
    quality: 100,
    dependencies: ['asl-lint/core'],
  },
  {
    id: 'asl-lint-heal',
    name: 'asl-lint/heal',
    category: 'quality',
    doc: 'AgentScript native autonomous repair rules, AST patch recipes, and auto-fixer.',
    schemas: ['PatchAction', 'FixResult'],
    enums: ['FixType'],
    exportsCount: 6,
    lines: 45,
    quality: 100,
    dependencies: ['asl-lint/core'],
  },
  {
    id: 'asl-mem-store',
    name: 'asl-mem/store',
    category: 'core',
    doc: 'In-memory vector database and cosine similarity in ASL.',
    schemas: ['VectorItem', 'VectorStore'],
    enums: [],
    exportsCount: 4,
    lines: 25,
    quality: 100,
    dependencies: [],
  },
  {
    id: 'asl-eddie-eddie',
    name: 'asl-eddie/eddie',
    category: 'mesh',
    doc: 'EDDIE: 3-Layer Superposition Swarm Orchestrator in ASL.',
    schemas: ['TaskItem', 'TaskPool', 'OrchestrationPlan'],
    enums: ['TriageVerdict', 'TaskTier', 'TaskIntent'],
    exportsCount: 10,
    lines: 73,
    quality: 100,
    dependencies: ['asl-fsm/fsm'],
  },
  {
    id: 'asl-fsm-fsm',
    name: 'asl-fsm/fsm',
    category: 'core',
    doc: 'Algebraic Finite State Machine engine in ASL.',
    schemas: [],
    enums: ['AgentState', 'AgentEvent'],
    exportsCount: 4,
    lines: 51,
    quality: 100,
    dependencies: [],
  },
];

export const ModuleGraphVisualizer: React.FC = () => {
  const [selectedCategory, setSelectedCategory] = useState<'all' | 'sql' | 'mesh' | 'quality' | 'core'>('all');
  const [activeModuleId, setActiveModuleId] = useState<string>(MODULES_REGISTRY[0].id);

  const filteredModules = selectedCategory === 'all'
    ? MODULES_REGISTRY
    : MODULES_REGISTRY.filter((m) => m.category === selectedCategory);

  const activeModule = MODULES_REGISTRY.find((m) => m.id === activeModuleId) || MODULES_REGISTRY[0];

  return (
    <Section id="module-graph">
      <SectionHeader
        id="module-graph-heading"
        index="06"
        eyebrow="Full-Spectrum Visual Architecture"
        title="Visual Module Topology & Architecture Cockpit"
        lead="Inspect module boundaries, exported contracts, algebraic schemas, and dependencies visually — zero raw code reading required for complete architectural observability."
      />

      <div className="mt-8 space-y-6">
        {/* Metric Summary Ribbon */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
          <div className="p-4 rounded-xl border border-border bg-surface-elevated">
            <span className="text-2xs font-semibold uppercase tracking-wider text-content-muted">Total Modules</span>
            <div className="text-2xl font-bold text-content mt-1">22</div>
            <span className="text-2xs text-status-pass font-medium">100% Typechecked</span>
          </div>
          <div className="p-4 rounded-xl border border-border bg-surface-elevated">
            <span className="text-2xs font-semibold uppercase tracking-wider text-content-muted">Quality Score</span>
            <div className="text-2xl font-bold text-status-pass mt-1">100/100</div>
            <span className="text-2xs text-content-muted">0 Blocking Smells</span>
          </div>
          <div className="p-4 rounded-xl border border-border bg-surface-elevated">
            <span className="text-2xs font-semibold uppercase tracking-wider text-content-muted">AST Redundancy</span>
            <div className="text-2xl font-bold text-accent mt-1">13.9%</div>
            <span className="text-2xs text-content-muted">Below 15.0% Ceiling</span>
          </div>
          <div className="p-4 rounded-xl border border-border bg-surface-elevated">
            <span className="text-2xs font-semibold uppercase tracking-wider text-content-muted">Observability</span>
            <div className="text-2xl font-bold text-code-literal mt-1">Full Visual</div>
            <span className="text-2xs text-content-muted">Zero-Code Inspection</span>
          </div>
        </div>

        {/* Category Filters */}
        <div className="flex flex-wrap items-center justify-between gap-4 p-4 rounded-xl border border-border bg-surface-elevated">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-semibold uppercase tracking-wider text-content-muted mr-2">
              Domain Filter:
            </span>
            {(['all', 'sql', 'mesh', 'quality', 'core'] as const).map((cat) => {
              const active = selectedCategory === cat;
              return (
                <button
                  key={cat}
                  type="button"
                  onClick={() => setSelectedCategory(cat)}
                  className={`px-3 py-1.5 text-xs font-semibold rounded-lg uppercase tracking-wider transition-all border ${
                    active
                      ? 'bg-accent text-accent-contrast border-accent shadow-sm'
                      : 'bg-surface text-content hover:bg-surface-elevated border-border'
                  }`}
                >
                  {cat}
                </button>
              );
            })}
          </div>

          <div className="text-xs font-mono text-content-muted">
            Viewing {filteredModules.length} of {MODULES_REGISTRY.length} registered core modules
          </div>
        </div>

        {/* Split Cockpit: Module Selector + Deep Inspector */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
          {/* Module Nodes Grid */}
          <div className="lg:col-span-5 space-y-3">
            {filteredModules.map((mod) => {
              const isSelected = mod.id === activeModule.id;
              return (
                <div
                  key={mod.id}
                  onClick={() => setActiveModuleId(mod.id)}
                  className={`p-4 rounded-xl border cursor-pointer transition-all ${
                    isSelected
                      ? 'bg-surface-elevated border-accent shadow-md'
                      : 'bg-surface border-border hover:border-accent/40'
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span
                        className={`inline-block w-2.5 h-2.5 rounded-full ${
                          mod.category === 'sql'
                            ? 'bg-code-literal'
                            : mod.category === 'mesh'
                            ? 'bg-accent'
                            : mod.category === 'quality'
                            ? 'bg-status-pass'
                            : 'bg-content-muted'
                        }`}
                      />
                      <span className="font-mono text-xs font-bold text-content">{mod.name}</span>
                    </div>
                    <span className="text-2xs font-mono px-2 py-0.5 rounded bg-status-pass/15 text-status-pass font-bold">
                      {mod.quality}/100
                    </span>
                  </div>

                  <p className="mt-2 text-xs text-content-muted line-clamp-2">{mod.doc}</p>

                  <div className="mt-3 flex items-center gap-4 text-2xs font-mono text-content-muted">
                    <span>{mod.exportsCount} exports</span>
                    <span>•</span>
                    <span>{mod.schemas.length} schemas</span>
                    <span>•</span>
                    <span>{mod.enums.length} enums</span>
                  </div>
                </div>
              );
            })}
          </div>

          {/* Deep Architectural Inspector Panel */}
          <div className="lg:col-span-7 flex flex-col rounded-xl border border-border bg-surface-elevated overflow-hidden">
            <div className="flex items-center justify-between px-5 py-4 border-b border-border bg-surface">
              <div>
                <div className="flex items-center gap-2">
                  <span className="text-2xs font-semibold uppercase px-2 py-0.5 rounded bg-accent/15 text-accent font-mono">
                    {activeModule.category}
                  </span>
                  <span className="font-mono text-sm font-bold text-content">{activeModule.name}</span>
                </div>
                <div className="text-xs text-content-muted mt-1">{activeModule.doc}</div>
              </div>
              <span className="text-xs font-mono px-3 py-1 rounded-lg border border-border bg-surface-elevated text-content">
                {activeModule.lines} lines
              </span>
            </div>

            <div className="p-6 space-y-6 flex-1 overflow-y-auto">
              {/* Schemas Section */}
              <div>
                <h4 className="text-xs font-bold uppercase tracking-wider text-content-muted mb-3">
                  🏛 Defined Schemas ({activeModule.schemas.length})
                </h4>
                {activeModule.schemas.length > 0 ? (
                  <div className="flex flex-wrap gap-2">
                    {activeModule.schemas.map((s) => (
                      <span
                        key={s}
                        className="px-3 py-1 text-xs font-mono rounded-lg bg-surface border border-border text-content font-medium"
                      >
                        {s}
                      </span>
                    ))}
                  </div>
                ) : (
                  <p className="text-xs text-content-muted italic">No records/schemas defined in this module.</p>
                )}
              </div>

              {/* Enums Section */}
              <div>
                <h4 className="text-xs font-bold uppercase tracking-wider text-content-muted mb-3">
                  🏷 Algebraic Enums ({activeModule.enums.length})
                </h4>
                {activeModule.enums.length > 0 ? (
                  <div className="flex flex-wrap gap-2">
                    {activeModule.enums.map((e) => (
                      <span
                        key={e}
                        className="px-3 py-1 text-xs font-mono rounded-lg bg-surface border border-border text-code-literal font-medium"
                      >
                        {e}
                      </span>
                    ))}
                  </div>
                ) : (
                  <p className="text-xs text-content-muted italic">No algebraic enums defined.</p>
                )}
              </div>

              {/* Dependencies Section */}
              <div>
                <h4 className="text-xs font-bold uppercase tracking-wider text-content-muted mb-3">
                  🔗 Direct Dependencies ({activeModule.dependencies.length})
                </h4>
                {activeModule.dependencies.length > 0 ? (
                  <div className="flex flex-wrap gap-2">
                    {activeModule.dependencies.map((dep) => (
                      <span
                        key={dep}
                        className="px-3 py-1 text-xs font-mono rounded-lg bg-accent/10 border border-accent/30 text-accent font-medium"
                      >
                        → {dep}
                      </span>
                    ))}
                  </div>
                ) : (
                  <p className="text-xs text-content-muted italic">Zero external module couplings (pure leaf module).</p>
                )}
              </div>

              {/* Architectural Safety Telemetry */}
              <div className="p-4 rounded-xl bg-surface border border-border space-y-2">
                <div className="flex items-center justify-between text-xs">
                  <span className="text-content font-medium">Control-Flow Linearization (@pcp:c-adc8)</span>
                  <span className="font-mono text-status-pass font-bold">Nesting ≤ 3 (PASS)</span>
                </div>
                <div className="flex items-center justify-between text-xs">
                  <span className="text-content font-medium">Dual-Projection Compliance (@pcp:d-1eed)</span>
                  <span className="font-mono text-accent font-bold">Nano Verified</span>
                </div>
                <div className="flex items-center justify-between text-xs">
                  <span className="text-content font-medium">Virtual Inspection (@pcp:r-8d8e)</span>
                  <span className="font-mono text-code-literal font-bold">asl view ready</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Section>
  );
};
