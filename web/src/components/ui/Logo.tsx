import React from 'react';

/**
 * ASL Iconic Mark & Cryptographic Core
 * The atomic shape of AgentScript: Two balanced parentheses enclosing a resonant core ( • )
 */
export const Logo: React.FC<{ className?: string; title?: string }> = ({
  className = 'w-8 h-8',
  title = 'ASL',
}) => (
  <svg viewBox="0 0 32 32" className={className} role="img" aria-label={title}>
    <defs>
      <linearGradient id="logoGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="rgb(var(--signal))" />
        <stop offset="100%" stopColor="rgb(var(--signal-soft))" />
      </linearGradient>
    </defs>
    {/* Left Paren Arc */}
    <path
      d="M12 5.5 C7.5 10 7.5 22 12 26.5"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.5"
      strokeLinecap="round"
    />
    {/* Right Paren Arc */}
    <path
      d="M20 5.5 C24.5 10 24.5 22 20 26.5"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.5"
      strokeLinecap="round"
    />
    {/* Core Quantum Emitter */}
    <circle cx="16" cy="16" r="3.5" fill="url(#logoGrad)" />
    <circle cx="16" cy="16" r="6" fill="none" stroke="rgb(var(--signal))" strokeWidth="0.75" strokeDasharray="2 2" opacity="0.6" />
  </svg>
);

/**
 * High-Density Brand Emblem / Visual Seal for Hero & Showcase
 */
export const Emblem: React.FC<{ className?: string }> = ({ className = 'w-24 h-24' }) => (
  <svg viewBox="0 0 96 96" className={className} fill="none" xmlns="http://www.w3.org/2000/svg">
    <defs>
      <radialGradient id="emblemCoreGlow" cx="50%" cy="50%" r="50%">
        <stop offset="0%" stopColor="rgb(var(--signal))" stopOpacity="0.4" />
        <stop offset="100%" stopColor="rgb(var(--signal))" stopOpacity="0" />
      </radialGradient>
      <linearGradient id="ringGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="rgb(var(--signal))" />
        <stop offset="100%" stopColor="currentColor" stopOpacity="0.3" />
      </linearGradient>
    </defs>
    
    {/* Outer Precision Ring */}
    <circle cx="48" cy="48" r="44" stroke="currentColor" strokeWidth="1" opacity="0.15" />
    <circle cx="48" cy="48" r="44" stroke="rgb(var(--signal))" strokeWidth="1.5" strokeDasharray="16 120" strokeLinecap="round" />
    
    {/* Ambient Core Glow */}
    <circle cx="48" cy="48" r="32" fill="url(#emblemCoreGlow)" />
    
    {/* Concentric Calibration Circles */}
    <circle cx="48" cy="48" r="30" stroke="currentColor" strokeWidth="0.75" strokeDasharray="3 6" opacity="0.25" />
    <circle cx="48" cy="48" r="20" stroke="currentColor" strokeWidth="1" opacity="0.2" />
    
    {/* Left Balanced Parenthesis */}
    <path
      d="M36 24 C24 34 24 62 36 72"
      stroke="currentColor"
      strokeWidth="4"
      strokeLinecap="round"
    />
    
    {/* Right Balanced Parenthesis */}
    <path
      d="M60 24 C72 34 72 62 60 72"
      stroke="currentColor"
      strokeWidth="4"
      strokeLinecap="round"
    />
    
    {/* Central Resonant Core */}
    <circle cx="48" cy="48" r="7" fill="rgb(var(--signal))" />
    <circle cx="48" cy="48" r="11" stroke="rgb(var(--signal))" strokeWidth="1.5" opacity="0.6" />
  </svg>
);

export const Wordmark: React.FC<{ className?: string }> = ({ className = '' }) => (
  <span className={`flex items-center gap-2.5 ${className}`}>
    <Logo className="w-7 h-7 text-ink" />
    <span className="font-sans font-semibold tracking-tight text-ink text-brand text-lg">ASL</span>
  </span>
);
