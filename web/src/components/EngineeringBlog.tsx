import React from 'react';
import { Section, SectionHeader } from './ui/primitives';

/*
  Withheld from the landing page until the essays are written out in full. The list stays
  fully expanded — an index that hides its own summaries is a worse index.
*/

const essays = [
  {
    date: '2026-09-01',
    kind: 'Language design',
    title: 'The death of syntax hallucinations',
    body: 'Why indentation and borrow-checked syntax cost a model four to eight repair loops, and what a balanced-parenthesis grammar removes from the problem.',
  },
  {
    date: '2026-08-28',
    kind: 'Architecture',
    title: 'Governing a swarm without reading its code',
    body: 'A four-layer zoom from the constitution down to the WASI trace, and why review has to move up the stack rather than get faster.',
  },
  {
    date: '2026-08-22',
    kind: 'Protocols',
    title: 'Beyond MCP: typed frames between agents',
    body: 'What natural-language agent chatter costs per turn, and what a typed S-expression frame replaces it with.',
  },
  {
    date: '2026-08-15',
    kind: 'Memory',
    title: 'Why agent memory belongs in version control',
    body: 'External vector stores detach from the code they describe. Decision records committed beside the code do not.',
  },
];

export const EngineeringBlog: React.FC = () => (
  <Section id="writing" labelledBy="writing-title">
    <SectionHeader
      id="writing-title"
      index="05"
      eyebrow="Writing"
      title="Notes on building a language for a generator."
    />

    <ol className="border-t border-line">
      {essays.map((e) => (
        <li key={e.title} className="py-8 border-b border-line">
          <a href="#writing" className="group grid grid-cols-1 md:grid-cols-[8rem_1fr] gap-x-8 gap-y-3">
            <span className="font-mono text-micro uppercase text-ink-3">
              <span className="block">{e.date}</span>
              <span className="block mt-1">{e.kind}</span>
            </span>
            <span>
              <span className="block text-h3 font-medium text-ink group-hover:text-signal transition-colors">
                {e.title}
              </span>
              <span className="block mt-3 text-body text-ink-2 max-w-prose">{e.body}</span>
            </span>
          </a>
        </li>
      ))}
    </ol>
  </Section>
);
