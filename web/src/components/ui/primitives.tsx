import React from 'react';

/*
  The exposed surface of the design system. Sections are assembled from these and nothing else,
  which is what keeps four sections from drifting into four private conventions.
*/

export const Section: React.FC<{
  id?: string;
  variant?: 'transparent' | 'surface' | 'sunken';
  ground?: 'ground' | 'sunken' | 'transparent';
  labelledBy?: string;
  className?: string;
  children: React.ReactNode;
}> = ({ id, variant, ground = 'ground', labelledBy, className = '', children }) => {
  const chosen = variant ?? (ground === 'transparent' ? 'transparent' : 'transparent');
  const bgStyles = {
    transparent: 'bg-transparent',
    surface: 'bg-transparent',
    sunken: 'bg-transparent',
  }[chosen];

  return (
    <section
      id={id}
      aria-labelledby={labelledBy}
      className={`relative py-28 sm:py-36 transition-colors ${bgStyles} ${className}`}
    >
      <div className="max-w-6xl mx-auto px-6 lg:px-8 relative z-10">{children}</div>
    </section>
  );
};

/* A numbered eyebrow. The index is the only ornament a section header gets. */
export const Eyebrow: React.FC<{ index?: string; children: React.ReactNode }> = ({
  index,
  children,
}) => (
  <span className="inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3">
    {index && <span className="text-signal">{index}</span>}
    <span className="w-8 h-px bg-line-strong" aria-hidden />
    {children}
  </span>
);

/*
  `align` is the only rhythm control a section header gets. Alternating it is what stops a page
  of stacked sections from reading as one template repeated.
*/
export const SectionHeader: React.FC<{
  id: string;
  index?: string;
  eyebrow: string;
  title: React.ReactNode;
  lead?: React.ReactNode;
  align?: 'left' | 'center';
}> = ({ id, index, eyebrow, title, lead, align = 'left' }) => (
  <header className={`mb-16 sm:mb-20 ${align === 'center' ? 'max-w-3xl mx-auto text-center' : 'max-w-3xl'}`}>
    <Eyebrow index={index}>{eyebrow}</Eyebrow>
    <h2 id={id} className="mt-6 text-h2 font-semibold text-ink text-balance">
      {title}
    </h2>
    {lead && (
      <p className={`mt-6 text-lead text-ink-2 max-w-prose ${align === 'center' ? 'mx-auto' : ''}`}>
        {lead}
      </p>
    )}
  </header>
);

