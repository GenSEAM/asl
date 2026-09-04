import React, { useState, useMemo, useEffect } from 'react';
import { useRouter } from '../lib/router';
import { BLOG_POSTS, getAllCategories, getRelatedPosts, getBlogPostBySlug } from '../lib/blog';
import { MarkdownRenderer } from '../lib/markdown';
import { SectionHeader } from '../components/ui/primitives';
import {
  Calendar,
  Clock,
  User,
  ArrowLeft,
  ArrowRight,
  Search,
  BookOpen,
  Share2,
  Check,
  Tag,
  Sparkles,
  ExternalLink
} from 'lucide-react';

export const BlogView: React.FC = () => {
  const { currentPath, navigate } = useRouter();

  // Determine if viewing a single post: /blog/:slug
  const activeSlug = useMemo(() => {
    const parts = currentPath.split('/').filter(Boolean);
    if (parts[0] === 'blog' && parts[1]) {
      return parts[1];
    }
    return null;
  }, [currentPath]);

  const activePost = useMemo(() => {
    if (!activeSlug) return null;
    return getBlogPostBySlug(activeSlug);
  }, [activeSlug]);

  useEffect(() => {
    if (activePost) {
      document.title = `${activePost.title} — AgentScript Blog`;
    } else if (activeSlug) {
      document.title = 'Essay Not Found — AgentScript Blog';
    } else {
      document.title = 'Engineering Blog — AgentScript (ASL)';
    }
  }, [activePost, activeSlug]);

  const [selectedCategory, setSelectedCategory] = useState<string>('All');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [copiedLink, setCopiedLink] = useState<boolean>(false);

  const categories = useMemo(() => [
    { name: 'All', count: BLOG_POSTS.length },
    ...getAllCategories()
  ], []);

  // Handle 404 for invalid essay slug
  if (activeSlug && !activePost) {
    return (
      <main className="flex-1 max-w-3xl mx-auto px-4 sm:px-6 py-16 sm:py-24 text-center">
        <div className="p-8 sm:p-12 border border-line rounded-xl bg-surface/80 backdrop-blur-md shadow-e2">
          <BookOpen className="w-12 h-12 text-ink-3 mx-auto mb-4" />
          <h1 className="text-xl sm:text-2xl font-bold text-ink mb-2">Essay Not Found</h1>
          <p className="text-sm text-ink-2 mb-6">
            The requested technical essay <code className="font-mono text-signal bg-surface-2 px-1.5 py-0.5 rounded border border-line">{activeSlug}</code> does not exist in our archive.
          </p>
          <button
            onClick={() => navigate('/blog')}
            className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-signal text-ground font-mono text-xs font-semibold hover:opacity-90 transition-opacity"
          >
            <ArrowLeft className="w-4 h-4" />
            <span>Browse All 7 Essays</span>
          </button>
        </div>
      </main>
    );
  }

  const filteredPosts = useMemo(() => {
    return BLOG_POSTS.filter((post) => {
      const matchesCategory =
        selectedCategory === 'All' ||
        post.category.toLowerCase() === selectedCategory.toLowerCase();

      const query = searchQuery.toLowerCase().trim();
      const matchesSearch =
        !query ||
        post.title.toLowerCase().includes(query) ||
        post.excerpt.toLowerCase().includes(query) ||
        post.tags.some((t) => t.toLowerCase().includes(query));

      return matchesCategory && matchesSearch;
    });
  }, [selectedCategory, searchQuery]);

  const handleShare = () => {
    navigator.clipboard.writeText(window.location.href);
    setCopiedLink(true);
    setTimeout(() => setCopiedLink(false), 2000);
  };

  // If viewing a specific article
  if (activePost) {
    const related = getRelatedPosts(activePost.slug, 2);
    const currentIndex = BLOG_POSTS.findIndex((p) => p.slug === activePost.slug);
    const prevPost = currentIndex > 0 ? BLOG_POSTS[currentIndex - 1] : null;
    const nextPost = currentIndex < BLOG_POSTS.length - 1 ? BLOG_POSTS[currentIndex + 1] : null;

    return (
      <main className="flex-1 max-w-4xl mx-auto px-4 sm:px-6 py-12 sm:py-16 w-full">
        {/* Navigation & Breadcrumbs */}
        <div className="flex items-center justify-between gap-4 mb-8 text-sm">
          <button
            onClick={() => navigate('/blog')}
            className="inline-flex items-center gap-2 text-ink-2 hover:text-signal transition-colors font-mono text-xs uppercase tracking-wider"
          >
            <ArrowLeft className="w-4 h-4" />
            <span>Back to all essays</span>
          </button>

          <button
            onClick={handleShare}
            className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded border border-line bg-surface hover:border-signal/50 text-ink-2 hover:text-ink transition-colors text-xs font-mono"
            title="Copy link to article"
          >
            {copiedLink ? <Check className="w-3.5 h-3.5 text-signal" /> : <Share2 className="w-3.5 h-3.5" />}
            <span>{copiedLink ? 'Link Copied' : 'Share'}</span>
          </button>
        </div>

        {/* Article Header Card */}
        <article className="border border-line rounded-xl bg-surface/80 p-6 sm:p-10 shadow-e2 relative overflow-hidden backdrop-blur-md">
          <div className="absolute top-0 right-0 w-64 h-64 bg-signal/5 rounded-full blur-3xl pointer-events-none" />

          <div className="flex flex-wrap items-center gap-3 text-xs font-mono text-ink-3 mb-4">
            <span className="px-2.5 py-0.5 rounded-full border border-signal/40 bg-signal/10 text-signal font-semibold uppercase tracking-wider">
              {activePost.category}
            </span>
            <span className="flex items-center gap-1">
              <Calendar className="w-3.5 h-3.5" />
              {activePost.date}
            </span>
            <span>•</span>
            <span className="flex items-center gap-1">
              <Clock className="w-3.5 h-3.5" />
              {activePost.readTime}
            </span>
            <span>•</span>
            <span className="flex items-center gap-1">
              <User className="w-3.5 h-3.5" />
              {activePost.author}
            </span>
          </div>

          <h1 className="text-2xl sm:text-4xl font-bold tracking-tight text-ink mb-6 leading-tight">
            {activePost.title}
          </h1>

          <p className="text-base sm:text-lg text-ink-2 leading-relaxed border-l-2 border-signal pl-4 italic mb-8 bg-surface-2/30 py-2 rounded-r">
            {activePost.excerpt}
          </p>

          <div className="flex flex-wrap gap-1.5 pt-4 border-t border-line/60 mb-8">
            {activePost.tags.map((tag) => (
              <span
                key={tag}
                className="inline-flex items-center gap-1 text-[11px] font-mono px-2 py-0.5 rounded bg-surface-2 text-ink-3 border border-line"
              >
                <Tag className="w-2.5 h-2.5" />
                {tag}
              </span>
            ))}
          </div>

          {/* Article Body */}
          <div className="pt-2">
            <MarkdownRenderer content={activePost.content} />
          </div>

          {/* Author Box */}
          <div className="mt-14 pt-8 border-t border-line flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 bg-surface-2/40 p-6 rounded-lg">
            <div>
              <div className="text-xs font-mono text-signal uppercase tracking-wider mb-1">Author</div>
              <div className="text-base font-semibold text-ink">{activePost.author}</div>
              <div className="text-xs text-ink-2 mt-1">
                Engineering team at AgentScript (ASL) — building deterministic runtime and language infrastructure for AI agents.
              </div>
            </div>
            <button
              onClick={() => navigate('/docs')}
              className="shrink-0 inline-flex items-center gap-1.5 px-3 py-1.5 rounded border border-line hover:border-signal text-xs font-mono text-ink hover:text-signal transition-colors bg-surface"
            >
              <span>Explore ASL Docs</span>
              <ExternalLink className="w-3 h-3" />
            </button>
          </div>
        </article>

        {/* Prev / Next Article Bar */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-8">
          {prevPost ? (
            <button
              onClick={() => navigate(`/blog/${prevPost.slug}`)}
              className="p-4 rounded-xl border border-line bg-surface/60 hover:border-signal/50 transition-all text-left group"
            >
              <span className="flex items-center gap-1 text-micro font-mono text-ink-3 uppercase mb-1">
                <ArrowLeft className="w-3 h-3 group-hover:-translate-x-1 transition-transform" />
                Previous Essay
              </span>
              <span className="block text-sm font-medium text-ink group-hover:text-signal transition-colors line-clamp-1">
                {prevPost.title}
              </span>
            </button>
          ) : <div />}

          {nextPost ? (
            <button
              onClick={() => navigate(`/blog/${nextPost.slug}`)}
              className="p-4 rounded-xl border border-line bg-surface/60 hover:border-signal/50 transition-all text-right group ml-auto w-full"
            >
              <span className="flex items-center justify-end gap-1 text-micro font-mono text-ink-3 uppercase mb-1">
                Next Essay
                <ArrowRight className="w-3 h-3 group-hover:translate-x-1 transition-transform" />
              </span>
              <span className="block text-sm font-medium text-ink group-hover:text-signal transition-colors line-clamp-1">
                {nextPost.title}
              </span>
            </button>
          ) : <div />}
        </div>

        {/* Related Articles */}
        {related.length > 0 && (
          <div className="mt-14 pt-8 border-t border-line">
            <h3 className="text-lg font-bold text-ink mb-6 flex items-center gap-2">
              <Sparkles className="w-4 h-4 text-signal" />
              Related Reading
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {related.map((post) => (
                <div
                  key={post.slug}
                  onClick={() => navigate(`/blog/${post.slug}`)}
                  className="p-5 rounded-lg border border-line bg-surface/60 hover:border-signal/50 cursor-pointer transition-all group"
                >
                  <div className="text-micro font-mono text-signal mb-1.5 uppercase">{post.category}</div>
                  <h4 className="text-sm font-semibold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2">
                    {post.title}
                  </h4>
                  <p className="text-xs text-ink-2 line-clamp-2">{post.excerpt}</p>
                </div>
              ))}
            </div>
          </div>
        )}
      </main>
    );
  }

  // Article Listing View: /blog
  return (
    <main className="flex-1 max-w-6xl mx-auto px-4 sm:px-6 py-12 sm:py-16 w-full">
      <SectionHeader
        id="blog-header"
        index="06"
        eyebrow="Engineering Blog & Technical Insights"
        title="Notes on building a language and infrastructure for synthetic intelligences."
      />

      {/* Intro Subtitle */}
      <p className="text-base sm:text-lg text-ink-2 max-w-3xl mb-10 leading-relaxed">
        Deep technical essays on compiler engineering, deterministic S-expressions, token economics,
        in-memory WebAssembly sandboxing, and inter-agent wire protocols. Designed for human engineers
        and structured for agentic RAG discovery.
      </p>

      {/* Filter and Search Bar */}
      <div className="flex flex-col md:flex-row items-stretch md:items-center justify-between gap-4 mb-8 pb-6 border-b border-line">
        {/* Category Pills */}
        <div className="flex flex-wrap items-center gap-1.5">
          {categories.map((cat) => (
            <button
              key={cat.name}
              onClick={() => setSelectedCategory(cat.name)}
              className={`px-3 py-1 rounded-full text-xs font-mono transition-colors border ${
                selectedCategory === cat.name
                  ? 'bg-signal text-ground font-semibold border-signal shadow-sm'
                  : 'bg-surface-2 text-ink-2 border-line hover:text-ink hover:border-line-2'
              }`}
            >
              {cat.name} <span className="opacity-60 text-[10px]">({cat.count})</span>
            </button>
          ))}
        </div>

        {/* Search Input */}
        <div className="relative min-w-[240px]">
          <Search className="w-4 h-4 text-ink-3 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="Search essays, tags, topics..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-9 pr-3 py-1.5 text-xs font-mono rounded-lg border border-line bg-surface text-ink placeholder:text-ink-3 focus:outline-none focus:border-signal transition-colors"
          />
        </div>
      </div>

      {/* Post Grid */}
      {filteredPosts.length === 0 ? (
        <div className="py-16 text-center border border-dashed border-line rounded-xl">
          <BookOpen className="w-8 h-8 text-ink-3 mx-auto mb-3" />
          <div className="text-base font-semibold text-ink">No matching essays found</div>
          <p className="text-xs text-ink-3 mt-1">Try selecting another category or clearing your search.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {filteredPosts.map((post) => (
            <article
              key={post.slug}
              onClick={() => navigate(`/blog/${post.slug}`)}
              className="p-6 sm:p-7 rounded-xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2"
            >
              <div>
                <div className="flex items-center justify-between text-micro font-mono text-ink-3 mb-3">
                  <span className="px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium">
                    {post.category}
                  </span>
                  <span>{post.readTime}</span>
                </div>

                <h2 className="text-lg sm:text-xl font-bold text-ink group-hover:text-signal transition-colors mb-3 leading-snug">
                  {post.title}
                </h2>

                <p className="text-sm text-ink-2 leading-relaxed mb-4 line-clamp-3">
                  {post.excerpt}
                </p>
              </div>

              <div>
                <div className="flex flex-wrap gap-1.5 mb-4">
                  {post.tags.slice(0, 3).map((tag) => (
                    <span
                      key={tag}
                      className="text-[10px] font-mono px-2 py-0.5 rounded bg-surface-2/60 text-ink-3 border border-line/60"
                    >
                      #{tag}
                    </span>
                  ))}
                  {post.tags.length > 3 && (
                    <span className="text-[10px] font-mono px-1.5 py-0.5 text-ink-3">
                      +{post.tags.length - 3}
                    </span>
                  )}
                </div>

                <div className="flex items-center justify-between pt-3 border-t border-line/50 text-xs font-mono text-ink-3">
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
      )}
    </main>
  );
};
