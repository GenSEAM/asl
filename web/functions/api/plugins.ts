export async function onRequestGet(context: any) {
  const url = new URL(context.request.url);
  const query = (url.searchParams.get("q") || "").toLowerCase();

  const plugins = [
    {
      name: "asl-github",
      repo: "github.com/GenSEAM/plugin-github",
      capability: "vcs",
      description: "Inspect repositories, read pull requests, and review diffs via GitHub API",
      author: "GenSEAM Core",
      stars: 142,
      version: "1.0.0"
    },
    {
      name: "asl-slack",
      repo: "github.com/GenSEAM/plugin-slack",
      capability: "chat",
      description: "Autonomous message dispatch, channel listener, and thread summarization",
      author: "community/alex",
      stars: 98,
      version: "1.0.0"
    },
    {
      name: "asl-postgres",
      repo: "github.com/GenSEAM/plugin-postgres",
      capability: "database",
      description: "Type-safe SQL query generation, schema inspection, and migration runner",
      author: "community/database-dao",
      stars: 215,
      version: "1.0.0"
    },
    {
      name: "asl-linear",
      repo: "github.com/GenSEAM/plugin-linear",
      capability: "pm",
      description: "Issue tracking, sprint planning, and automated roadmap synchronization",
      author: "community/pm-tools",
      stars: 86,
      version: "1.0.0"
    },
    {
      name: "asl-searxng",
      repo: "github.com/GenSEAM/search",
      capability: "search",
      description: "Zero-telemetry SearXNG metasearch aggregator and proxy rotation pool",
      author: "GenSEAM Core",
      stars: 310,
      version: "1.0.0"
    }
  ];

  const filtered = query
    ? plugins.filter(p => p.name.toLowerCase().includes(query) || p.description.toLowerCase().includes(query) || p.capability.toLowerCase().includes(query))
    : plugins;

  return new Response(JSON.stringify({ total: filtered.length, plugins: filtered }, null, 2), {
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "public, max-age=60, s-maxage=300"
    }
  });
}
