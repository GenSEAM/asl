import React from 'react';
import StudioViewAsl from './StudioView.asl';
import { InBrowserCompanion } from '../components/InBrowserCompanion';

export const StudioView: React.FC = () => {
  return (
    <div className="pb-20">
      <StudioViewAsl />
      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 -mt-6">
        <InBrowserCompanion />
      </div>
    </div>
  );
};

export default StudioView;
