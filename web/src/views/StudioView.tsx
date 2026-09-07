import React from 'react';
import { Section, SectionHeader } from '../components/ui/primitives';
import { InBrowserCompanion } from '../components/InBrowserCompanion';

export const StudioView: React.FC = () => {
  return (
    <div className="pt-28 pb-20">
      <Section id="studio" labelledBy="studio-title">
        <SectionHeader
          id="studio-title"
          index="Tri-Studio"
          eyebrow="On-Device Agent Creator Studio"
          title="Synthesize SVG Art, Playable Games & Responsive Websites"
          lead="Powered by on-board WebGPU micro-models with zero server roundtrips. Draw vector emblems, build playable 2D arcade games, and author responsive website components verified through client-side gates."
        />

        <div className="mt-6">
          <InBrowserCompanion />
        </div>
      </Section>
    </div>
  );
};
