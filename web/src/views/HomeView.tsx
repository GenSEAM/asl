import React from 'react';
import { Hero } from '../components/Hero';
import { KeyCapabilities } from '../components/KeyCapabilities';
import { TheAgentWay } from '../components/TheAgentWay';
import { AgentWireProtocol } from '../components/AgentWireProtocol';
import { HarnessToolkit } from '../components/HarnessToolkit';
import { ModuleGraphVisualizer } from '../components/ModuleGraphVisualizer';
import { Ecosystem } from '../components/Ecosystem';

export const HomeView: React.FC = () => (
  <main className="flex-1">
    <Hero />
    <Ecosystem />
    <KeyCapabilities />
    <TheAgentWay />
    <AgentWireProtocol />
    <HarnessToolkit />
    <ModuleGraphVisualizer />
  </main>
);
