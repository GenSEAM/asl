import React, { useEffect, useRef, useState } from 'react';
import { ArrowRight, Check, Copy } from 'lucide-react';
import { Sexpr } from './ui/primitives';

const INSTALL = 'curl -fsSL https://aslang.dev/install.sh | bash';

// Taken verbatim from the conformance corpus, so the specimen is the language, not a mock-up.
const SPECIMEN = [
  '(defschema Point',
  '  (:field x Int64)',
  '  (:field y Int64))',
  '',
  '(defun manhattan [(p Point) (q Point)] -> Int64',
  '  (+ (abs (- (.-x p) (.-x q)))',
  '     (abs (- (.-y p) (.-y q)))))',
  '',
  '(defun scale [(p Point) (k Int64)] -> Point',
  '  (Point :x (* (.-x p) k)',
  '         :y (* (.-y p) k)))',
];

const TARGETS = ['Python', 'Rust', 'WebAssembly', 'TypeScript', 'Go', 'Interpreter'];

export const Hero: React.FC = () => {
  const [copied, setCopied] = useState(false);
  const [failed, setFailed] = useState(false);
  const timer = useRef<number | undefined>(undefined);

  useEffect(() => () => window.clearTimeout(timer.current), []);

  // The Clipboard API is absent on insecure origins and rejects when permission is denied;
  // the command itself stays select-all so the fallback is to select it by hand.
  const copy = async () => {
    let ok = true;
    try {
      await navigator.clipboard.writeText(INSTALL);
    } catch {
      ok = false;
    }
    setCopied(ok);
    setFailed(!ok);
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      setCopied(false);
      setFailed(false);
    }, 2000);
  };

  return (
    <section id="top" className="relative bg-ground pt-40 pb-24 sm:pt-48 sm:pb-32">
      <div className="max-w-6xl mx-auto px-6 lg:px-8">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-16 lg:gap-12 items-center">
          <div className="lg:col-span-6">
            <span className="inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3">
              <span className="w-1.5 h-1.5 rounded-full bg-signal" aria-hidden />
              A language written for the generator
            </span>

            <h1 className="mt-8 text-display font-semibold text-ink text-balance">
              Code an agent can<br className="hidden sm:block" /> write correctly the
              <span className="text-signal"> first time.</span>
            </h1>

            <p className="mt-8 text-lead text-ink-2 max-w-prose">
              AgentScript is an S-expression language with a single-pass LL(1) grammar. There is no
              significant whitespace to hallucinate and no bracket a parser has to guess at — so a
              model emits a program once instead of repairing one four times.
            </p>

            <div className="mt-10 flex flex-wrap items-center gap-3">
              <a
                href="#agent-way"
                className="inline-flex items-center gap-2 px-7 py-3.5 rounded-full bg-ink text-ground font-medium text-body hover:opacity-90 transition-opacity"
              >
                Read the idea
                <ArrowRight className="w-4 h-4" aria-hidden />
              </a>
              <a
                href="#toolchain"
                className="inline-flex items-center gap-2 px-7 py-3.5 rounded-full border border-line-strong text-ink font-medium text-body hover:bg-surface transition-colors"
              >
                The toolchain
              </a>
            </div>

            <div id="install" className="mt-8 flex items-center gap-3 max-w-lg">
              <code className="flex-1 min-w-0 font-mono text-meta text-ink-2 truncate select-all">
                <span className="text-ink-3">$ </span>
                {INSTALL}
              </code>
              <button
                type="button"
                onClick={copy}
                className="shrink-0 inline-flex items-center gap-1.5 font-mono text-meta text-ink-3 hover:text-ink transition-colors"
              >
                {copied ? <Check className="w-3.5 h-3.5" aria-hidden /> : <Copy className="w-3.5 h-3.5" aria-hidden />}
                {copied ? 'Copied' : failed ? 'Select it' : 'Copy'}
              </button>
              <span aria-live="polite" className="sr-only">
                {copied ? 'Install command copied to clipboard' : ''}
                {failed ? 'Clipboard unavailable. Select the command to copy it.' : ''}
              </span>
            </div>
          </div>

          {/* The specimen is the hero image. A program set well says more than a render of a sphere. */}
          <figure className="lg:col-span-6 lg:-mr-8 xl:-mr-16">
            <div className="rounded-2xl border border-line bg-surface shadow-e3 overflow-hidden">
              <div className="flex items-center justify-between px-6 py-3.5 border-b border-line">
                <span className="font-mono text-micro uppercase text-ink-3">point.agentscript</span>
                <span className="font-mono text-micro uppercase text-ink-3">Balanced · 1 pass</span>
              </div>
              <pre className="px-6 py-7 overflow-x-auto text-code">
                {SPECIMEN.map((line, i) => (
                  <span key={i} className="grid grid-cols-[2rem_1fr]">
                    <span className="font-mono text-ink-3 select-none tabular-nums text-micro pt-[0.3em]">
                      {i + 1}
                    </span>
                    <Sexpr code={line} className="text-ink" />
                  </span>
                ))}
              </pre>
            </div>
            <figcaption className="sr-only">
              A record definition and a function from the ASL conformance corpus.
            </figcaption>
          </figure>
        </div>

        {/* One source, six targets — stated as a measure rather than a claim. */}
        <div className="mt-24 sm:mt-32">
          <div className="rule-fade" aria-hidden />
          <div className="mt-8 flex flex-wrap items-baseline gap-x-10 gap-y-4">
            <span className="font-mono text-micro uppercase text-ink-3">One source compiles to</span>
            {TARGETS.map((t) => (
              <span key={t} className="font-mono text-meta text-ink-2">
                {t}
              </span>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};
