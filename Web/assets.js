// The base URL is generated at build time, outside the source repository.
export function assetBase(value, relativeTo) {
  if (typeof value !== 'string' || !value.trim()) throw new Error('The asset library is not configured.');
  const base = new URL(value, relativeTo);
  const local = ['localhost', '127.0.0.1', '[::1]'].includes(base.hostname);
  if (!(base.protocol === 'https:' || (base.protocol === 'http:' && local)) ||
      base.username || base.password || base.search || base.hash) {
    throw new Error('The asset library address must be HTTPS.');
  }
  if (!base.pathname.endsWith('/')) base.pathname += '/';
  return base;
}

export function assetURL(base, path) {
  if (!/^(catalog\.json|objects\/[a-f0-9]{64}\.(wav|m4a))$/.test(path)) {
    throw new Error('Invalid asset path in the catalog.');
  }
  return new URL(path, base);
}
