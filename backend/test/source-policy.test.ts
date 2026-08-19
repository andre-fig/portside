import { describe, expect, it } from 'vitest';
import { validateHTTPSHost, validateStorageKey } from '../src/source-policy.js';

describe('source policy', () => {
  const hosts = new Set(['github.com']);
  it('accepts only allowlisted HTTPS hosts', () => { expect(validateHTTPSHost('https://github.com/example/release', hosts).hostname).toBe('github.com'); });
  it('rejects redirects/hosts outside the allowlist before download', () => { expect(() => validateHTTPSHost('http://github.com/example', hosts)).toThrow(); expect(() => validateHTTPSHost('https://evil.example/example', hosts)).toThrow(); });
  it('rejects unsafe storage keys', () => { expect(() => validateStorageKey('../escape')).toThrow(); expect(validateStorageKey('artifacts/a.zip')).toBe('artifacts/a.zip'); });
});
