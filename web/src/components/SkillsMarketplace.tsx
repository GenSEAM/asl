import React from 'react';
import { Section, SectionHeader } from './ui/primitives';

/*
  Withheld from the landing page until the registry is public. Presented as a manifest rather
  than a storefront: every package, its scope and its install line, all on screen at once.
*/

const packages = [
  { pkg: '@genseam/asl', name: 'Language core', scope: 'Grammar, checker, standard library' },
  { pkg: '@genseam/harness', name: 'Agent harness', scope: 'Intent classification and task pools' },
  { pkg: '@genseam/skills', name: 'Skills hub', scope: 'Prompt skills and tool adapters' },
  { pkg: '@genseam/agent-bus', name: 'Socket bus', scope: 'In-memory socket and SSE transport' },
  { pkg: '@genseam/browser-plugin', name: 'Browser lens', scope: 'DOM extraction and in-situ actions' },
  { pkg: '@genseam/in-browser-dev', name: 'In-browser dev', scope: 'Hot-reloading Wasm runtime' },
  { pkg: '@genseam/search', name: 'Search scout', scope: 'Metasearch and RAG compression' },
  { pkg: '@genseam/mem', name: 'Vector memory', scope: 'Local cosine recall in WebAssembly' },
];

export const SkillsMarketplace: React.FC = () => (
  <Section id="packages" labelledBy="packages-title">
    <SectionHeader
      id="packages-title"
      index="06"
      eyebrow="Packages"
      title="Everything the toolchain ships, in one manifest."
    />

    <ul className="border-t border-line">
      {packages.map((p) => (
        <li
          key={p.pkg}
          className="grid grid-cols-1 md:grid-cols-[14rem_1fr_auto] gap-x-8 gap-y-2 py-6 border-b border-line items-baseline"
        >
          <span className="text-body font-medium text-ink">{p.name}</span>
          <span className="text-body text-ink-2">{p.scope}</span>
          <code className="font-mono text-meta text-ink-3 whitespace-nowrap">
            <span className="text-signal">$ </span>asl skill install {p.pkg}
          </code>
        </li>
      ))}
    </ul>
  </Section>
);
