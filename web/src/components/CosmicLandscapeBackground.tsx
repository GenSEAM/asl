import React from 'react';
import { ChameleonSchematic } from './ui/Logo';

/**
 * CosmicLandscapeBackground
 * Clean, calm, and elegant unified background used uniformly across all pages:
 * 1. Fixed schematic chameleon mascot perched in the top-left (below floating navbar)
 * 2. Deep atmospheric violet & cosmic indigo glowing lighting auras
 * 3. Subtle, high-end blueprint grid texture
 */
export const CosmicLandscapeBackground: React.FC = () => (
  <div className="fixed inset-0 pointer-events-none select-none overflow-hidden z-0" aria-hidden="true">
    {/* Atmospheric bioluminescent lighting auras */}
    <div className="absolute top-12 left-8 w-[550px] h-[550px] bg-purple-600/15 dark:bg-purple-900/25 blur-[150px] rounded-full" />
    <div className="absolute top-1/3 right-8 w-[650px] h-[650px] bg-indigo-600/12 dark:bg-indigo-950/20 blur-[160px] rounded-full" />
    <div className="absolute bottom-16 left-1/4 w-[700px] h-[550px] bg-purple-900/15 blur-[160px] rounded-full" />

    {/* Subtle Architectural Blueprint Grid */}
    <div className="absolute inset-0 bg-blueprint-grid opacity-30 dark:opacity-25" />

    {/* Fixed Schematic Chameleon Watermark in Upper-Left (perched under floating navbar) */}
    <div className="fixed top-20 left-2 sm:left-6 lg:left-10 w-72 sm:w-84 lg:w-[440px] h-auto opacity-20 dark:opacity-25 transition-all z-10">
      <ChameleonSchematic
        className="w-full h-auto text-signal"
        strokeWidth={2.0}
        glow={true}
      />
    </div>
  </div>
);
