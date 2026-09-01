import React from 'react';

/*
  The mark is the atom of the language: `( • )`. Two parens enclosing a single evaluated
  core — the smallest well-formed S-expression, and the one shape the whole product is built on.
  Stroke stays on currentColor so the mark inherits ink; only the core carries the signal.
*/
export const Logo: React.FC<{ className?: string; title?: string }> = ({
  className = 'w-8 h-8',
  title = 'ASL',
}) => (
  <svg viewBox="0 0 32 32" className={className} role="img" aria-label={title}>
    <path
      d="M11.6 4.4a15.5 15.5 0 0 0 0 23.2"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.4"
      strokeLinecap="round"
    />
    <path
      d="M20.4 4.4a15.5 15.5 0 0 1 0 23.2"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.4"
      strokeLinecap="round"
    />
    <circle cx="16" cy="16" r="4" fill="rgb(var(--signal))" />
  </svg>
);

export const Wordmark: React.FC<{ className?: string }> = ({ className = '' }) => (
  <span className={`flex items-center gap-2.5 ${className}`}>
    <Logo className="w-7 h-7 text-ink" />
    <span className="font-sans font-semibold text-ink text-brand">ASL</span>
  </span>
);
