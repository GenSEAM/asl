import React from 'react';
import { Section, SectionHeader } from './ui/primitives';

interface Epoch {
  era: string;
  name: string;
  thesis: string;
  designedFor: string;
  cost: string[];
  current?: boolean;
}

const epochs: Epoch[] = [
  {
    era: '1990s',
    name: 'Object-oriented',
    thesis: 'Structure the program the way a team can divide it.',
    designedFor: 'A team of typists',
    cost: ['Rigid hierarchies', 'Mutation hazards'],
  },
  {
    era: '2010s',
    name: 'Functional',
    thesis: 'Make state explicit so concurrency stops being folklore.',
    designedFor: 'A reasoning human',
    cost: ['Type acrobatics', 'Runtime overhead'],
  },
  {
    era: '2023',
    name: 'Prompt and pray',
    thesis: 'Ask a model for a language built for someone else, then fix what comes back.',
    designedFor: 'Nobody',
    cost: ['Whitespace crashes', 'Repair loops', 'Context exhaustion'],
  },
  {
    era: '2026',
    name: 'Agentic',
    thesis: 'Give the generator a grammar it cannot get wrong, and check every target agrees.',
    designedFor: 'The generator',
    cost: [],
    current: true,
  },
];

export const TheAgentWay: React.FC = () => (
  <Section id="agent-way" labelledBy="agent-way-title" variant="sunken">
    <SectionHeader
      id="agent-way-title"
      index="01"
      eyebrow="The idea"
      title="Every language so far was designed for the hands that typed it."
      lead="That was the right constraint for thirty years. It stopped being the right one the moment most code started arriving from a model — which is a generator with no fingers, no editor and no second chance at a bracket."
    />

    <ol className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 border-t border-line">
      {epochs.map((e) => (
        <li
          key={e.era}
          className="relative pt-8 pb-10 lg:pr-8 border-b border-line lg:border-b-0 lg:border-r last:border-r-0 lg:pl-8 first:lg:pl-0"
        >
          {/* The live era is marked on the rule itself, not by tinting its card. */}
          {e.current && (
            <span
              className="absolute -top-[3px] left-0 lg:left-8 w-8 h-1 rounded-full bg-signal"
              aria-hidden
            />
          )}

          <p className="font-mono text-micro uppercase text-ink-3">{e.era}</p>
          <h3
            className={`mt-4 text-h3 ${e.current ? 'font-semibold text-ink' : 'font-medium text-ink-2'}`}
          >
            {e.name}
          </h3>
          <p className="mt-4 text-body text-ink-2">{e.thesis}</p>

          <p className="mt-7 font-mono text-micro uppercase text-ink-3">Designed for</p>
          <p className={`mt-1.5 text-body ${e.current ? 'text-signal font-medium' : 'text-ink-2'}`}>
            {e.designedFor}
          </p>

          {e.cost.length > 0 && (
            <>
              <p className="mt-7 font-mono text-micro uppercase text-ink-3">What it cost a model</p>
              <ul className="mt-1.5 space-y-1">
                {e.cost.map((c) => (
                  <li key={c} className="text-body text-ink-2">
                    {c}
                  </li>
                ))}
              </ul>
            </>
          )}
        </li>
      ))}
    </ol>

    <div className="mt-16 sm:mt-20 grid grid-cols-1 lg:grid-cols-12 gap-10 items-start">
      <p className="lg:col-span-5 text-h3 font-medium text-ink text-balance">
        Balance is a property, not a convention.
      </p>
      <p className="lg:col-span-7 text-lead text-ink-2 max-w-prose">
        An indentation-sensitive language asks a model to hold invisible state across a hundred
        lines. A balanced-parenthesis one asks it to close what it opened — a check the parser makes
        in a single left-to-right pass, and the one structural mistake a generator is least able to
        make silently.
      </p>
    </div>
  </Section>
);
