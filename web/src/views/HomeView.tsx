import React from 'react';
import { Hero } from '../components/Hero';
import { Ecosystem } from '../components/Ecosystem';
import { KeyCapabilities } from '../components/KeyCapabilities';
import { TheAgentWay } from '../components/TheAgentWay';
import { InBrowserAgent } from '../components/InBrowserAgent';
import { AgentWireProtocol } from '../components/AgentWireProtocol';
import { HarnessToolkit } from '../components/HarnessToolkit';
import { ModuleGraphVisualizer } from '../components/ModuleGraphVisualizer';
import { EngineeringBlog } from '../components/EngineeringBlog';

export const HomeView: React.FC = () => (
  <main className="flex-1">
    <Hero />
    <Ecosystem />
    <KeyCapabilities />
    <TheAgentWay />
    <AgentWireProtocol />
    <HarnessToolkit />
    <ModuleGraphVisualizer />
    <EngineeringBlog />
    <InBrowserAgent />
  </main>
);
