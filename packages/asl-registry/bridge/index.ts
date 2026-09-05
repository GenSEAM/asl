/**
 * Universal Multi-Ecosystem Package Registry Bridge for AgentScript
 */

export type Ecosystem = 'asl' | 'npm' | 'pypi' | 'crates' | 'go' | 'github';

export interface PackageMeta {
  name: string;
  ecosystem: Ecosystem;
  latestVersion: string;
  description: string;
  license: string;
  homepage: string;
  recentReleases: string[];
}

export async function fetchPackageMeta(eco: Ecosystem, name: string): Promise<PackageMeta> {
  const cleanName = encodeURIComponent(name);
  let url = '';
  let headers: Record<string, string> = {
    'User-Agent': 'ASL-Registry/0.3.0 (+https://aslang.dev)',
    'Accept': 'application/json',
  };

  switch (eco) {
    case 'npm':
      url = `https://registry.npmjs.org/${cleanName}`;
      headers['Accept'] = 'application/vnd.npm.install-v1+json';
      break;
    case 'pypi':
      url = `https://pypi.org/pypi/${cleanName}/json`;
      break;
    case 'crates':
      url = `https://crates.io/api/v1/crates/${cleanName}`;
      break;
    case 'go':
      url = `https://proxy.golang.org/${cleanName}/@latest`;
      break;
    case 'github':
    case 'asl':
      url = `https://api.github.com/repos/${name}/releases?per_page=5`;
      headers['Accept'] = 'application/vnd.github.v3+json';
      break;
  }

  const res = await fetch(url, { headers });
  if (!res.ok) {
    throw new Error(`Registry request failed for ${eco}:${name} with HTTP ${res.status}`);
  }

  const data = await res.json();

  if (eco === 'npm') {
    const latest = data['dist-tags']?.latest || '0.0.0';
    const verInfo = data.versions?.[latest] || {};
    return {
      name,
      ecosystem: 'npm',
      latestVersion: latest,
      description: data.description || verInfo.description || '',
      license: verInfo.license || data.license || 'Unknown',
      homepage: data.homepage || `https://www.npmjs.com/package/${name}`,
      recentReleases: Object.keys(data.versions || {}).slice(-5),
    };
  }

  if (eco === 'pypi') {
    const info = data.info || {};
    return {
      name,
      ecosystem: 'pypi',
      latestVersion: info.version || '0.0.0',
      description: info.summary || '',
      license: info.license || 'Unknown',
      homepage: info.home_page || `https://pypi.org/project/${name}/`,
      recentReleases: Object.keys(data.releases || {}).slice(-5),
    };
  }

  if (eco === 'crates') {
    const krate = data.crate || {};
    return {
      name,
      ecosystem: 'crates',
      latestVersion: krate.max_version || '0.0.0',
      description: krate.description || '',
      license: data.versions?.[0]?.license || 'Unknown',
      homepage: krate.homepage || krate.repository || `https://crates.io/crates/${name}`,
      recentReleases: (data.versions || []).slice(0, 5).map((v: any) => v.num),
    };
  }

  return {
    name,
    ecosystem: eco,
    latestVersion: data.Version || data[0]?.tag_name || '0.0.0',
    description: data.description || '',
    license: 'Unknown',
    homepage: `https://github.com/${name}`,
    recentReleases: Array.isArray(data) ? data.map(r => r.tag_name) : [],
  };
}
