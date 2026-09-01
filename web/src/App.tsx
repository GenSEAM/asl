import React from 'react';
import { ThemeProvider } from './lib/theme';
import { Navbar } from './components/Navbar';
import { Hero } from './components/Hero';
import { EddieOrchestrator } from './components/EddieOrchestrator';
import { AgentSwarmVisualizer } from './components/AgentSwarmVisualizer';
import { SkillsMarketplace } from './components/SkillsMarketplace';
import { CommunityHub } from './components/CommunityHub';
import { TokenCalculator } from './components/TokenCalculator';
import { Ecosystem } from './components/Ecosystem';
import { Footer } from './components/Footer';

export const App: React.FC = () => {
  return (
    <ThemeProvider>
      <div className="min-h-screen bg-white dark:bg-craft-950 text-craft-900 dark:text-craft-100 flex flex-col selection:bg-craft-accent/30 selection:text-craft-900 dark:selection:text-white transition-colors">
        <Navbar />
        <main className="flex-1 space-y-0">
          <Hero />
          <EddieOrchestrator />
          <AgentSwarmVisualizer />
          <SkillsMarketplace />
          <CommunityHub />
          <TokenCalculator />
          <Ecosystem />
        </main>
        <Footer />
      </div>
    </ThemeProvider>
  );
};

export default App;
