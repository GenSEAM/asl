import React, { useState } from 'react';
import { Section, SectionHeader } from './ui/primitives';

type ScenarioKey = 'clean' | 'smells' | 'clones';

interface Scenario {
  title: string;
  badge: string;
  initialCode: string;
  repairedCode?: string;
  initialScore: number;
  repairedScore?: number;
  initialErrors: number;
  initialWarnings: number;
  duplicateNodes: number;
  duplicationRatio: string;
  smells: Array<{ code: string; severity: 'error' | 'warning'; message: string; fixable: boolean }>;
}

const SCENARIOS: Record<ScenarioKey, Scenario> = {
  clean: {
    title: '1. Canonical Clean Module',
    badge: '100/100 (Pass)',
    initialCode: `; Canonical ASL Module with docstrings and explicit exports
(module math/core
  :doc "Pure arithmetic helpers and vector operations."
  :export [add dot-product])

(defun add [(a Int64) (b Int64)] -> Int64
  :doc "Adds two 64-bit integers."
  (+ a b))

(defun dot-product [(x1 Int64) (y1 Int64) (x2 Int64) (y2 Int64)] -> Int64
  :doc "Computes 2D vector dot product."
  (+ (* x1 x2) (* y1 y2)))`,
    initialScore: 100,
    initialErrors: 0,
    initialWarnings: 0,
    duplicateNodes: 0,
    duplicationRatio: '0.0%',
    smells: [],
  },
  smells: {
    title: '2. Smell & Anti-Pattern Detection',
    badge: '65/100 (Needs Repair)',
    initialCode: `; Anti-pattern: Unused binding & unexported referenced schema type
(module service/config
  :doc "Service configuration and runtime mode."
  :export [Config])

(defenum Mode
  (:case fast [] "Optimized fast mode")
  (:case slow [] "Thorough slow mode"))

(defschema Config
  (:field mode Mode "Runtime execution mode"))

(defun compute [(n Int64)] -> Int64
  :doc "Computes runtime metric"
  (let [(dead-val 42)
        (live-val 10)]
    (+ n live-val)))`,
    repairedCode: `; Auto-repaired by native asl-lint/heal engine
(module service/config
  :doc "Service configuration and runtime mode."
  :export [Config Mode])

(defenum Mode
  (:case fast [] "Optimized fast mode")
  (:case slow [] "Thorough slow mode"))

(defschema Config
  (:field mode Mode "Runtime execution mode"))

(defun compute [(n Int64)] -> Int64
  :doc "Computes runtime metric"
  (let [(unused-dead-val 42)
        (live-val 10)]
    (+ n live-val)))`,
    initialScore: 65,
    repairedScore: 100,
    initialErrors: 1,
    initialWarnings: 1,
    duplicateNodes: 0,
    duplicationRatio: '0.0%',
    smells: [
      {
        code: 'rule-13',
        severity: 'error',
        message: "Mode in exported field Config.mode is declared here and not exported",
        fixable: true,
      },
      {
        code: 'unused-binding',
        severity: 'warning',
        message: "Unused variable binding 'dead-val'; prefix with 'unused-'",
        fixable: true,
      },
    ],
  },
  clones: {
    title: '3. AST Structural Clone & Duplication',
    badge: '33.3% Duplication',
    initialCode: `; Redundant AST copy-paste with renamed variables across functions
(module finance/tax
  :doc "Tax calculations"
  :export [calc-personal calc-corporate])

(defun calc-personal [(income Int64) (rate Int64)] -> Int64
  :doc "Personal tax calculation"
  (let [(subtotal (* (+ income 100) rate))]
    (+ subtotal 50)))

(defun calc-corporate [(revenue Int64) (margin Int64)] -> Int64
  :doc "Corporate tax calculation with alpha-equivalent AST subtree"
  (let [(res (* (+ revenue 100) margin))]
    (+ res 50)))`,
    repairedCode: `; Refactored: Subtree extracted into reusable helper
(module finance/tax
  :doc "Tax calculations with extracted AST kernel"
  :export [calc-personal calc-corporate])

(defun apply-tax-bracket [(base Int64) (multiplier Int64)] -> Int64
  :doc "Shared parameterized calculation kernel"
  (let [(subtotal (* (+ base 100) multiplier))]
    (+ subtotal 50)))

(defun calc-personal [(income Int64) (rate Int64)] -> Int64
  :doc "Personal tax calculation"
  (apply-tax-bracket income rate))

(defun calc-corporate [(revenue Int64) (margin Int64)] -> Int64
  :doc "Corporate tax calculation"
  (apply-tax-bracket revenue margin))`,
    initialScore: 75,
    repairedScore: 100,
    initialErrors: 0,
    initialWarnings: 2,
    duplicateNodes: 14,
    duplicationRatio: '33.3%',
    smells: [
      {
        code: 'structural-clone',
        severity: 'warning',
        message: 'Identical AST subtree detected in calc-corporate (matches calc-personal)',
        fixable: true,
      },
    ],
  },
};

const VERIFICATION_GATES = [
  { step: '1/7', name: 'Grammar Conformance & Parity', tool: 'validate.py', status: 'PASS' },
  { step: '2/7', name: 'Vocabulary & Call-Head Closure', tool: 'closure_audit.py', status: '107/107 (100%)' },
  { step: '3/7', name: 'Prelude Generator & Lowering Check', tool: 'generate.py --check', status: 'PASS' },
  { step: '4/7', name: 'Semantic Type & Scope Checker Gate', tool: 'checker/gate.py', status: 'PASS' },
  { step: '5/7', name: 'Native ASL Quality & Smell Engine', tool: 'agentscript lint', status: '0 ERRORS' },
  { step: '6/7', name: 'AST Structural Clone & Duplication Gate', tool: 'agentscript clone-check', status: '3.3% < 15%' },
  { step: '7/7', name: 'Design Tokens & Cloudflare Pages Pre-Flight', tool: 'deploy_check.py', status: 'PASS' },
];

export const AslQualityDoctor: React.FC = () => {
  const [activeScenario, setActiveScenario] = useState<ScenarioKey>('smells');
  const [isRepaired, setIsRepaired] = useState(false);

  const scenario = SCENARIOS[activeScenario];
  const currentCode = isRepaired && scenario.repairedCode ? scenario.repairedCode : scenario.initialCode;
  const currentScore = isRepaired && scenario.repairedScore !== undefined ? scenario.repairedScore : scenario.initialScore;
  const currentErrors = isRepaired ? 0 : scenario.initialErrors;
  const currentWarnings = isRepaired ? 0 : scenario.initialWarnings;
  const currentSmells = isRepaired ? [] : scenario.smells;

  const handleSelectScenario = (key: ScenarioKey) => {
    setActiveScenario(key);
    setIsRepaired(false);
  };

  return (
    <Section id="quality-doctor" ground="sunken">
      <SectionHeader
        id="quality-doctor-heading"
        index="04"
        eyebrow="Quality Doctor & Self-Healing"
        title="Native ASL Quality Tools, Smell Detection & Autonomous Repair"
        lead="AgentScript implements its entire quality analysis suite, structural clone detection, and self-healing engine in native .asl files. Quality is an architectural property verified before every single commit."
      />

      {/* Interactive Scenario Tabs */}
      <div className="flex flex-wrap gap-2 mb-8 border-b border-line pb-4">
        {(Object.keys(SCENARIOS) as ScenarioKey[]).map((key) => {
          const s = SCENARIOS[key];
          const active = activeScenario === key;
          return (
            <button
              key={key}
              onClick={() => handleSelectScenario(key)}
              className={`px-4 py-2 rounded font-mono text-sm transition-colors border ${
                active
                  ? 'bg-surface text-ink border-signal font-semibold'
                  : 'bg-ground text-ink-2 border-line hover:text-ink hover:border-line-strong'
              }`}
            >
              {s.title}
            </button>
          );
        })}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
        {/* Code Editor & Viewer */}
        <div className="lg:col-span-7 bg-ground border border-line rounded-lg overflow-hidden flex flex-col shadow-sm">
          <div className="flex items-center justify-between px-4 py-3 bg-surface border-b border-line text-xs font-mono">
            <span className="text-ink-2 font-medium flex items-center gap-2">
              <span className="w-2.5 h-2.5 rounded-full bg-signal inline-block" />
              {activeScenario}.asl
              {isRepaired && <span className="text-signal font-semibold">[Repaired]</span>}
            </span>
            {scenario.repairedCode && (
              <button
                onClick={() => setIsRepaired(!isRepaired)}
                className={`px-3 py-1 rounded text-xs font-medium transition-all ${
                  isRepaired
                    ? 'bg-inset text-ink border border-line hover:bg-surface'
                    : 'bg-signal text-ground font-semibold hover:opacity-90 shadow-sm'
                }`}
              >
                {isRepaired ? '↺ Reset to Original' : '⚡ Autonomous Auto-Repair (asl fix)'}
              </button>
            )}
          </div>
          <pre className="p-4 text-xs font-mono leading-relaxed overflow-x-auto text-ink bg-inset">
            <code>{currentCode}</code>
          </pre>
        </div>

        {/* Quality Diagnostics & Scorecard */}
        <div className="lg:col-span-5 flex flex-col gap-6">
          {/* Scorecard Box */}
          <div className="bg-surface border border-line rounded-lg p-5 flex flex-col gap-4">
            <div className="flex items-center justify-between border-b border-line pb-3">
              <span className="font-mono text-xs uppercase tracking-wider text-ink-3">Maintainability & Quality Score</span>
              <span
                className={`font-mono text-xl font-bold px-2.5 py-0.5 rounded ${
                  currentScore >= 90
                    ? 'text-signal bg-ground border border-signal'
                    : 'text-ink-2 bg-ground border border-line'
                }`}
              >
                {currentScore}/100
              </span>
            </div>

            <div className="grid grid-cols-3 gap-2 text-center font-mono text-xs">
              <div className="p-2 bg-ground rounded border border-line">
                <span className="text-ink-3 block mb-1">Errors</span>
                <span className={`font-bold ${currentErrors > 0 ? 'text-signal' : 'text-ink'}`}>{currentErrors}</span>
              </div>
              <div className="p-2 bg-ground rounded border border-line">
                <span className="text-ink-3 block mb-1">Warnings</span>
                <span className="font-bold text-ink">{currentWarnings}</span>
              </div>
              <div className="p-2 bg-ground rounded border border-line">
                <span className="text-ink-3 block mb-1">Duplication</span>
                <span className="font-bold text-ink">{isRepaired ? '0.0%' : scenario.duplicationRatio}</span>
              </div>
            </div>

            {/* Diagnostic list */}
            <div className="mt-2 flex flex-col gap-2">
              <span className="font-mono text-xs uppercase text-ink-3">Active Invariants & Diagnostics:</span>
              {currentSmells.length === 0 ? (
                <div className="p-3 bg-ground rounded border border-line text-xs font-mono text-ink flex items-center gap-2">
                  <span className="text-signal font-bold">✓</span> Clean: 0 Anti-patterns detected. Pre-commit gate accepts clean.
                </div>
              ) : (
                currentSmells.map((s, i) => (
                  <div key={i} className="p-3 bg-ground rounded border border-line text-xs font-mono flex flex-col gap-1">
                    <div className="flex items-center justify-between">
                      <span className="font-bold text-signal">[{s.code}]</span>
                      {s.fixable && <span className="text-ink-3 text-micro uppercase">[Auto-Fixable]</span>}
                    </div>
                    <span className="text-ink-2">{s.message}</span>
                  </div>
                ))
              )}
            </div>
          </div>

          {/* Verification Chain Box */}
          <div className="bg-surface border border-line rounded-lg p-5 flex flex-col gap-3">
            <span className="font-mono text-xs uppercase tracking-wider text-ink-3 border-b border-line pb-2">
              ASL Pre-Commit 7-Gate Chain
            </span>
            <div className="flex flex-col gap-2">
              {VERIFICATION_GATES.map((g, idx) => (
                <div key={idx} className="flex items-center justify-between text-xs font-mono">
                  <span className="text-ink-2">
                    <span className="text-ink-3 mr-2">{g.step}</span>
                    {g.name}
                  </span>
                  <span className="text-signal font-medium bg-ground px-2 py-0.5 rounded border border-line">
                    ✓ {g.status}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </Section>
  );
};

export default AslQualityDoctor;
