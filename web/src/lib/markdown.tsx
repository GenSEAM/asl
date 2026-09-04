import React, { useState } from 'react';
import { Copy, Check } from 'lucide-react';

interface MarkdownRendererProps {
  content: string;
}

export const MarkdownRenderer: React.FC<MarkdownRendererProps> = ({ content }) => {
  // Strip the leading H1 if it matches the article title
  const cleanContent = content.replace(/^#\s+[^\n]+\n/, '');

  const renderInline = (text: string): React.ReactNode => {
    // Process code, bold, italic, and links
    const parts: React.ReactNode[] = [];
    let remaining = text;
    let key = 0;

    // Pattern for inline code, bold, italic, links
    const inlineRegex = /(`([^`]+)`)|(\*\*([^*]+)\*\*)|(\*([^*]+)\*)|(\[([^\]]+)\]\(([^)]+)\))/;

    while (remaining) {
      const match = remaining.match(inlineRegex);
      if (!match || match.index === undefined) {
        parts.push(remaining);
        break;
      }

      if (match.index > 0) {
        parts.push(remaining.slice(0, match.index));
      }

      const fullMatch = match[0];
      if (match[1]) {
        // Inline code
        parts.push(
          <code key={key++} className="font-mono text-[0.88em] bg-surface-2 text-signal px-1.5 py-0.5 rounded border border-line">
            {match[2]}
          </code>
        );
      } else if (match[3]) {
        // Bold
        parts.push(
          <strong key={key++} className="font-semibold text-ink">
            {match[4]}
          </strong>
        );
      } else if (match[5]) {
        // Italic
        parts.push(
          <em key={key++} className="italic text-ink-2">
            {match[6]}
          </em>
        );
      } else if (match[7]) {
        // Link
        parts.push(
          <a
            key={key++}
            href={match[9]}
            className="text-signal hover:underline transition-colors"
            target={match[9].startsWith('http') ? '_blank' : undefined}
            rel={match[9].startsWith('http') ? 'noopener noreferrer' : undefined}
          >
            {match[8]}
          </a>
        );
      }

      remaining = remaining.slice(match.index + fullMatch.length);
    }

    return parts;
  };

  // Split content into blocks
  const lines = cleanContent.split('\n');
  const blocks: React.ReactNode[] = [];
  let blockKey = 0;

  let i = 0;
  while (i < lines.length) {
    const line = lines[i];

    // Fenced Code Block
    if (line.startsWith('```')) {
      const lang = line.slice(3).trim() || 'text';
      const codeLines: string[] = [];
      i++;
      while (i < lines.length && !lines[i].startsWith('```')) {
        codeLines.push(lines[i]);
        i++;
      }
      i++; // skip closing ```
      const rawCode = codeLines.join('\n');

      blocks.push(
        <CodeBlock key={blockKey++} code={rawCode} language={lang} />
      );
      continue;
    }

    // Markdown Table
    if (line.startsWith('|') && line.endsWith('|')) {
      const tableLines: string[] = [];
      while (i < lines.length && lines[i].startsWith('|') && lines[i].endsWith('|')) {
        tableLines.push(lines[i]);
        i++;
      }
      blocks.push(<TableBlock key={blockKey++} lines={tableLines} renderInline={renderInline} />);
      continue;
    }

    // Headings
    if (line.startsWith('## ')) {
      const headingText = line.slice(3).trim();
      const id = headingText.toLowerCase().replace(/[^\w]+/g, '-');
      blocks.push(
        <h2 key={blockKey++} id={id} className="text-2xl font-bold tracking-tight text-ink mt-10 mb-4 pt-4 border-t border-line/60">
          {renderInline(headingText)}
        </h2>
      );
      i++;
      continue;
    }

    if (line.startsWith('### ')) {
      const headingText = line.slice(4).trim();
      const id = headingText.toLowerCase().replace(/[^\w]+/g, '-');
      blocks.push(
        <h3 key={blockKey++} id={id} className="text-xl font-semibold text-ink mt-8 mb-3">
          {renderInline(headingText)}
        </h3>
      );
      i++;
      continue;
    }

    if (line.startsWith('#### ')) {
      const headingText = line.slice(5).trim();
      blocks.push(
        <h4 key={blockKey++} className="text-lg font-medium text-ink mt-6 mb-2">
          {renderInline(headingText)}
        </h4>
      );
      i++;
      continue;
    }

    // Horizontal Rule
    if (/^---+\s*$/.test(line)) {
      blocks.push(<hr key={blockKey++} className="my-8 border-line" />);
      i++;
      continue;
    }

    // Blockquote
    if (line.startsWith('> ')) {
      const quoteLines: string[] = [];
      while (i < lines.length && lines[i].startsWith('>')) {
        quoteLines.push(lines[i].replace(/^>\s?/, ''));
        i++;
      }
      blocks.push(
        <blockquote key={blockKey++} className="border-l-2 border-signal/60 bg-surface-2/40 px-4 py-3 my-5 italic text-ink-2 rounded-r">
          {quoteLines.map((ql, qidx) => (
            <p key={qidx} className="my-1">{renderInline(ql)}</p>
          ))}
        </blockquote>
      );
      continue;
    }

    // Bullet list
    if (/^\s*[-*]\s+/.test(line)) {
      const listItems: string[] = [];
      while (i < lines.length && /^\s*[-*]\s+/.test(lines[i])) {
        listItems.push(lines[i].replace(/^\s*[-*]\s+/, ''));
        i++;
      }
      blocks.push(
        <ul key={blockKey++} className="list-disc list-outside pl-6 my-4 space-y-2 text-ink-2">
          {listItems.map((item, lidx) => (
            <li key={lidx}>{renderInline(item)}</li>
          ))}
        </ul>
      );
      continue;
    }

    // Numbered list
    if (/^\s*\d+\.\s+/.test(line)) {
      const listItems: string[] = [];
      while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
        listItems.push(lines[i].replace(/^\s*\d+\.\s+/, ''));
        i++;
      }
      blocks.push(
        <ol key={blockKey++} className="list-decimal list-outside pl-6 my-4 space-y-2 text-ink-2">
          {listItems.map((item, lidx) => (
            <li key={lidx}>{renderInline(item)}</li>
          ))}
        </ol>
      );
      continue;
    }

    // Blank line
    if (!line.trim()) {
      i++;
      continue;
    }

    // Regular paragraph
    const paragraphLines: string[] = [line];
    i++;
    while (
      i < lines.length &&
      lines[i].trim() &&
      !lines[i].startsWith('#') &&
      !lines[i].startsWith('```') &&
      !lines[i].startsWith('|') &&
      !lines[i].startsWith('> ') &&
      !/^\s*[-*]\s+/.test(lines[i]) &&
      !/^\s*\d+\.\s+/.test(lines[i]) &&
      !/^---+\s*$/.test(lines[i])
    ) {
      paragraphLines.push(lines[i]);
      i++;
    }

    blocks.push(
      <p key={blockKey++} className="my-4 leading-relaxed text-ink-2">
        {renderInline(paragraphLines.join(' '))}
      </p>
    );
  }

  return <div className="markdown-body space-y-2 text-[15px] sm:text-[16px] text-ink">{blocks}</div>;
};

const CodeBlock: React.FC<{ code: string; language: string }> = ({ code, language }) => {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="my-6 rounded-lg border border-line bg-surface/95 overflow-hidden shadow-sm">
      <div className="flex items-center justify-between px-3 py-1.5 border-b border-line/70 bg-surface-2/60 text-micro font-mono text-ink-3">
        <span className="uppercase tracking-wider">{language}</span>
        <button
          onClick={handleCopy}
          className="flex items-center gap-1 hover:text-ink transition-colors px-2 py-0.5 rounded text-micro"
          title="Copy code"
        >
          {copied ? <Check className="w-3.5 h-3.5 text-signal" /> : <Copy className="w-3.5 h-3.5" />}
          <span>{copied ? 'Copied' : 'Copy'}</span>
        </button>
      </div>
      <pre className="p-4 overflow-x-auto text-[13px] font-mono leading-relaxed text-ink bg-ground/50">
        <code>{code}</code>
      </pre>
    </div>
  );
};

const TableBlock: React.FC<{
  lines: string[];
  renderInline: (text: string) => React.ReactNode;
}> = ({ lines, renderInline }) => {
  if (lines.length < 2) return null;

  const parseRow = (line: string) =>
    line
      .slice(1, -1)
      .split('|')
      .map((c) => c.trim());

  const headers = parseRow(lines[0]);
  const rows = lines.slice(2).map(parseRow);

  return (
    <div className="my-6 overflow-x-auto rounded-lg border border-line">
      <table className="w-full text-left text-sm border-collapse">
        <thead>
          <tr className="bg-surface-2/70 border-b border-line text-ink font-semibold">
            {headers.map((h, idx) => (
              <th key={idx} className="py-2.5 px-3.5">
                {renderInline(h)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-line/60">
          {rows.map((row, rIdx) => (
            <tr key={rIdx} className="hover:bg-surface-2/30 transition-colors">
              {row.map((cell, cIdx) => (
                <td key={cIdx} className="py-2 px-3.5 text-ink-2 font-mono text-[13px]">
                  {renderInline(cell)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};
