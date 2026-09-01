import React from 'react';
import { Navbar } from './components/Navbar';
import { Hero } from './components/Hero';
import { ShowcaseGallery } from './components/ShowcaseGallery';
import { AgentHarness } from './components/AgentHarness';
import { Playground } from './components/Playground';
import { GraphVisualizer } from './components/GraphVisualizer';
import { VectorClassifier } from './components/VectorClassifier';
import { TargetMatrix } from './components/TargetMatrix';
import { RuntimeMatrix } from './components/RuntimeMatrix';
import { TokenCalculator } from './components/TokenCalculator';
import { ParadigmBridge } from './components/ParadigmBridge';
import { FrameworkBridges } from './components/FrameworkBridges';
import { AslVdomRenderer } from './components/AslVdomRenderer';
import { BestPractices } from './components/BestPractices';
import { CommunityHub } from './components/CommunityHub';
import { Blog } from './components/Blog';
import { Docs } from './components/Docs';
import { Ecosystem } from './components/Ecosystem';
import { Footer } from './components/Footer';

export const App: React.FC = () => {
  return (
    <div className="min-h-screen bg-craft-950 text-craft-100 flex flex-col">
      <Navbar />
      <main className="flex-1">
        <Hero />
        <ShowcaseGallery />
        <AgentHarness />
        <CommunityHub />
        <Playground />
        <GraphVisualizer />
        <VectorClassifier />
        <FrameworkBridges />
        <AslVdomRenderer />
        <ParadigmBridge />
        <TargetMatrix />
        <RuntimeMatrix />
        <TokenCalculator />
        <BestPractices />
        <Blog />
        <Docs />
        <Ecosystem />
      </main>
      <Footer />
    </div>
  );
};

export default App;
