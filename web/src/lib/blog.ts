import { BLOG_POSTS, BlogPost, getBlogPostBySlug, getFeaturedBlogPosts } from '../data/blog/posts';

export type { BlogPost };
export { BLOG_POSTS, getBlogPostBySlug, getFeaturedBlogPosts };

export interface BlogCategory {
  name: string;
  count: number;
}

export const getAllCategories = (): BlogCategory[] => {
  const counts: Record<string, number> = {};
  BLOG_POSTS.forEach((p) => {
    counts[p.category] = (counts[p.category] || 0) + 1;
  });
  return Object.entries(counts).map(([name, count]) => ({ name, count }));
};

export const getPostsByCategory = (category: string): BlogPost[] => {
  if (!category || category.toLowerCase() === 'all') return BLOG_POSTS;
  return BLOG_POSTS.filter((p) => p.category.toLowerCase() === category.toLowerCase());
};

export const getRelatedPosts = (currentSlug: string, limit: number = 2): BlogPost[] => {
  const current = getBlogPostBySlug(currentSlug);
  if (!current) return BLOG_POSTS.slice(0, limit);
  return BLOG_POSTS.filter(
    (p) => p.slug !== currentSlug && (p.category === current.category || p.tags.some((t) => current.tags.includes(t)))
  ).slice(0, limit);
};
