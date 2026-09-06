import React from 'react';
import { Section, SectionHeader } from '../components/ui/primitives';
import { InBrowserCompanion } from '../components/InBrowserCompanion';

export const PlaygroundView: React.FC = () => {
  return (
    <div className="pt-28 pb-20">
      <Section id="playground" labelledBy="playground-title">
        <SectionHeader
          id="playground-title"
          index="Interactive"
          eyebrow="Agent Sandbox"
          title="In-Browser Autonomous Agent Studio"
          lead="Experience 100% client-side WebGPU agent intelligence executing inside an isolated sandbox. Generates live interactive apps, games, and vector graphics with zero cloud roundtrips."
        />

        {/* Clean Main Sandbox Workspace */}
        <div className="rounded-3xl border border-line bg-surface/90 backdrop-blur-xl p-4 sm:p-6 shadow-e3">
          <InBrowserCompanion />
        </div>
      </Section>
    </div>
  );
};

