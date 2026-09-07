import React from 'react';
import PlaygroundViewAsl from './PlaygroundView.asl';
import { InBrowserCompanion } from '../components/InBrowserCompanion';

export const PlaygroundView: React.FC = () => {
  return (
    <div className="pb-20">
      <PlaygroundViewAsl />
      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 -mt-4">
        <InBrowserCompanion />
      </div>
    </div>
  );
};

export default PlaygroundView;
