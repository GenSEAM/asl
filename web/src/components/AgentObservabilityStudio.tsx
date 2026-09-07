import React from 'react';
import { Section, SectionHeader } from './ui/primitives';

/*
  Withheld from the landing page until it stands on its own. Kept on the token system so it
  re-enters the page already consistent with it.
*/

const layers = [
  {
    index: '01',
    name: 'Strategic',
    where: '.asl/constitution.md',
    body: 'The goals, the guardrails and the architectural boundaries a swarm is not allowed to cross. Written by a person, versioned with the code.',
  },
  {
    index: '02',
    name: 'Tactical',
    where: 'In-memory socket bus',
    body: 'How work was decomposed and which specialist took which part. The layer where drift becomes visible before it becomes a diff.',
  },
  {
    index: '03',
    name: 'Operational',
    where: '.asl/mem/',
    body: 'Decision records and requirements as first-class versioned files, so branching a repository branches what the agent believes about it.',
  },
  {
    index: '04',
    name: 'Physical',
    where: 'WASI isolate',
    body: 'What actually executed, inside a sandbox with no host disk. The only layer that can contradict the other three.',
  },
];

export const AgentObservabilityStudio: React.FC = () => (
  <Section id="observability" ground="sunken" labelledBy="observability-title">
    <SectionHeader
      id="observability-title"
      index="04"
      eyebrow="Observability"
      title="Nobody reads fifty thousand lines a day."
      lead="Review does not scale by reading faster. It scales by moving up: four layers, each one answering a different question, each one able to be checked without opening the one below it."
    />

    <ol className="border-t border-line">
      {layers.map((l) => (
        <li
          key={l.index}
          className="grid grid-cols-1 md:grid-cols-[4rem_12rem_1fr] gap-x-8 gap-y-3 py-8 border-b border-line"
        >
          <span className="font-mono text-micro uppercase text-signal">{l.index}</span>
          <span>
            <span className="block text-h3 font-medium text-ink">{l.name}</span>
            <span className="block mt-1.5 font-mono text-micro uppercase text-ink-3">{l.where}</span>
          </span>
          <p className="text-body text-ink-2 max-w-prose">{l.body}</p>
        </li>
      ))}
    </ol>

    <p className="mt-10 font-mono text-meta text-ink-3">
      <span className="text-signal">$ </span>asl inspect
    </p>
  </Section>
);
