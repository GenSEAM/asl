import React from 'react';
import { ThemeProvider } from './lib/theme';
import { Navbar } from './components/Navbar';
import { Hero } from './components/Hero';
import { TheAgentWay } from './components/TheAgentWay';
import { AgentWireProtocol } from './components/AgentWireProtocol';
import { SkyLoomVisualizer } from './components/SkyLoomVisualizer';
import { AslQualityDoctor } from './components/AslQualityDoctor';
import { SqlStudio } from './components/SqlStudio';
import { ModuleGraphVisualizer } from './components/ModuleGraphVisualizer';
import { Ecosystem } from './components/Ecosystem';
import { Footer } from './components/Footer';

export const App: React.FC = () => (
  <ThemeProvider>
    <div className="min-h-screen bg-ground text-ink flex flex-col">
      <Navbar />
      <main className="flex-1">
        <Hero />
        <TheAgentWay />
        <AgentWireProtocol />
        <SkyLoomVisualizer />
        <AslQualityDoctor />
        <SqlStudio />
        <ModuleGraphVisualizer />
        <Ecosystem />
      </main>
      <Footer />
    </div>
  </ThemeProvider>
);

export default App;
