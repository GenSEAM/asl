import React from 'react';
import { Section, SectionHeader } from './ui/primitives';
import { useRouter } from '../lib/router';
import { BLOG_POSTS } from '../lib/blog';
import { ArrowRight, BookOpen, Clock, Tag } from 'lucide-react';

export const EngineeringBlog: React.FC = () => {
  const { navigate } = useRouter();

  return (
    <Section id="writing" labelledBy="writing-title">
      <div className="flex flex-col sm:flex-row sm:items-end justify-between gap-4 mb-2">
        <SectionHeader
          id="writing-title"
          index="05"
          eyebrow="Engineering Blog"
          title="Notes on building a language and infrastructure for synthetic intelligences."
        />
        <button
          onClick={() => navigate('/blog')}
          className="shrink-0 mb-4 inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-line hover:border-signal text-xs font-mono text-ink-2 hover:text-signal transition-colors bg-surface/80"
        >
          <span>View All Essays</span>
          <ArrowRight className="w-3.5 h-3.5" />
        </button>
      </div>

      <p className="text-sm sm:text-base text-ink-2 max-w-3xl mb-8 leading-relaxed">
        Deep architectural notes from the AgentScript systems group: why LLMs struggle with whitespace
        and borrow checkers, how AST interface compression eliminates the 78% token tax, and how in-memory
        WASI execution runs test suites in 0.04ms.
      </p>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 border-t border-line pt-8">
        {BLOG_POSTS.slice(0, 4).map((post) => (
          <article
            key={post.slug}
            onClick={() => navigate(`/blog/${post.slug}`)}
            className="p-6 rounded-xl border border-line bg-surface/60 hover:bg-surface/90 hover:border-signal/50 cursor-pointer transition-all duration-200 group flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between text-micro font-mono text-ink-3 mb-2.5">
                <span className="px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-semibold">
                  {post.category}
                </span>
                <span className="flex items-center gap-1">
                  <Clock className="w-3 h-3" />
                  {post.readTime}
                </span>
              </div>

              <h3 className="text-base sm:text-lg font-bold text-ink group-hover:text-signal transition-colors mb-2.5 leading-snug">
                {post.title}
              </h3>

              <p className="text-xs sm:text-sm text-ink-2 leading-relaxed mb-4 line-clamp-3">
                {post.excerpt}
              </p>
            </div>

            <div>
              <div className="flex flex-wrap gap-1.5 mb-3">
                {post.tags.slice(0, 3).map((t) => (
                  <span
                    key={t}
                    className="inline-flex items-center gap-0.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-surface-2 text-ink-3 border border-line/60"
                  >
                    <Tag className="w-2.5 h-2.5" />
                    {t}
                  </span>
                ))}
              </div>

              <div className="flex items-center justify-between pt-2.5 border-t border-line/50 text-xs font-mono text-ink-3">
                <span>{post.date}</span>
                <span className="flex items-center gap-1 text-signal group-hover:translate-x-0.5 transition-transform font-medium">
                  <span>Read Essay</span>
                  <ArrowRight className="w-3.5 h-3.5" />
                </span>
              </div>
            </div>
          </article>
        ))}
      </div>

      <div className="mt-8 pt-6 border-t border-line flex justify-center">
        <button
          onClick={() => navigate('/blog')}
          className="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg border border-line bg-surface hover:border-signal text-sm font-mono text-ink hover:text-signal transition-all shadow-sm group"
        >
          <BookOpen className="w-4 h-4 text-signal" />
          <span>Explore All 7 Technical Essays in the Blog</span>
          <ArrowRight className="w-4 h-4 group-hover:translate-x-0.5 transition-transform" />
        </button>
      </div>
    </Section>
  );
};
