import React from 'react';
import { ThemeProvider } from './lib/theme';
import { Navbar } from './components/Navbar';
import { Hero } from './components/Hero';
import { TheAgentWay } from './components/TheAgentWay';
import { AgentWireProtocol } from './components/AgentWireProtocol';
import { VisualCognition } from './components/VisualCognition';
import { DesignSystemExplorer } from './components/DesignSystemExplorer';
import { EcosystemGlue } from './components/EcosystemGlue';
import { EddieOrchestrator } from './components/EddieOrchestrator';
import { AgentSwarmVisualizer } from './components/AgentSwarmVisualizer';
import { SkillsMarketplace } from './components/SkillsMarketplace';
import { TokenCalculator } from './components/TokenCalculator';
import { Ecosystem } from './components/Ecosystem';
import { Footer } from './components/Footer';

export const App: React.FC = () => {
  return (
    <ThemeProvider>
      <div className="min-h-screen bg-white dark:bg-[#030508] text-craft-900 dark:text-craft-100 flex flex-col selection:bg-craft-accent/30 selection:text-craft-900 dark:selection:text-white transition-colors">
        <Navbar />
        <main className="flex-1 space-y-0">
          <Hero />
          <TheAgentWay />
          <AgentWireProtocol />
          <VisualCognition />
          <DesignSystemExplorer />
          <EcosystemGlue />
          <EddieOrchestrator />
          <AgentSwarmVisualizer />
          <SkillsMarketplace />
          <TokenCalculator />
          <Ecosystem />
        </main>
        <Footer />
      </div>
    </ThemeProvider>
  );
};

export default App;
