import {
  PAYMENT_RETURN_PATH,
  parseHttpOrigin,
  parseOriginList,
  resolvePaymentReturnUrl,
} from './payment-return-url';

describe('parseHttpOrigin', () => {
  it('keeps only the origin of an http(s) URL', () => {
    expect(parseHttpOrigin('http://localhost:5173')).toBe('http://localhost:5173');
    expect(parseHttpOrigin('https://app.example.com/some/path?x=1#frag')).toBe('https://app.example.com');
    expect(parseHttpOrigin('  https://app.example.com  ')).toBe('https://app.example.com');
  });

  it('rejects non-http schemes, credentials and garbage', () => {
    expect(parseHttpOrigin('myapp://wallet/topup-result')).toBeNull();
    expect(parseHttpOrigin('javascript:alert(1)')).toBeNull();
    expect(parseHttpOrigin('https://user:pass@example.test')).toBeNull();
    expect(parseHttpOrigin('not a url')).toBeNull();
    expect(parseHttpOrigin('')).toBeNull();
    expect(parseHttpOrigin(undefined)).toBeNull();
  });
});

describe('parseOriginList', () => {
  it('splits, normalises, dedupes and drops invalid entries', () => {
    expect(parseOriginList('http://a.test, https://b.test/', 'http://a.test,myapp://x')).toEqual([
      'http://a.test',
      'https://b.test',
    ]);
  });

  it('returns an empty list for missing input', () => {
    expect(parseOriginList(undefined, null, '')).toEqual([]);
  });
});

describe('resolvePaymentReturnUrl', () => {
  const ENV_KEYS = ['CORS_ORIGINS', 'CLIENT_ORIGIN', 'KASHIER_REDIRECT_URL'] as const;
  const savedEnv: Record<string, string | undefined> = {};

  beforeAll(() => {
    for (const key of ENV_KEYS) savedEnv[key] = process.env[key];
  });

  afterAll(() => {
    for (const key of ENV_KEYS) {
      if (savedEnv[key] === undefined) delete process.env[key];
      else process.env[key] = savedEnv[key];
    }
  });

  beforeEach(() => {
    for (const key of ENV_KEYS) delete process.env[key];
  });

  it('uses a configured URL verbatim, including its path and query', () => {
    expect(
      resolvePaymentReturnUrl({
        origin: 'http://localhost:5173',
        allowList: 'http://localhost:5173',
        configuredRedirectUrl: 'https://tunnel.test/api/v1/payment-return?source=kashier#top',
      }),
    ).toBe('https://tunnel.test/api/v1/payment-return?source=kashier#top');
  });

  it('falls back to KASHIER_REDIRECT_URL from the environment', () => {
    process.env.KASHIER_REDIRECT_URL = 'https://tunnel.test/api/v1/payment-return';
    expect(resolvePaymentReturnUrl({})).toBe('https://tunnel.test/api/v1/payment-return');
  });

  it('ignores an invalid configured URL and uses the allow-listed request origin', () => {
    expect(
      resolvePaymentReturnUrl({
        origin: 'http://localhost:5173',
        allowList: 'http://localhost:5173',
        configuredRedirectUrl: 'myapp://wallet/topup-result',
      }),
    ).toBe(`http://localhost:5173${PAYMENT_RETURN_PATH}`);
  });

  it('never carries a path or query from the request origin', () => {
    const url = resolvePaymentReturnUrl({
      origin: 'http://localhost:5173/evil?next=//attacker',
      allowList: 'http://localhost:5173',
    });
    expect(url).toBe(`http://localhost:5173${PAYMENT_RETURN_PATH}`);
    expect(url).not.toContain('evil');
  });

  it('falls back to CLIENT_ORIGIN for an unknown/missing origin', () => {
    expect(
      resolvePaymentReturnUrl({
        origin: 'https://evil.example',
        allowList: 'http://localhost:5173',
        clientOrigin: 'http://localhost:5174',
      }),
    ).toBe(`http://localhost:5174${PAYMENT_RETURN_PATH}`);
    expect(
      resolvePaymentReturnUrl({ allowList: 'http://localhost:5173', clientOrigin: 'http://localhost:5174' }),
    ).toBe(`http://localhost:5174${PAYMENT_RETURN_PATH}`);
  });

  it('returns null when no http(s) candidate exists', () => {
    expect(
      resolvePaymentReturnUrl({ allowList: '', configuredRedirectUrl: 'myapp://wallet/topup-result' }),
    ).toBeNull();
    expect(resolvePaymentReturnUrl({ allowList: '' })).toBeNull();
  });

  it('treats the configured app origin as allow-listed implicitly', () => {
    expect(
      resolvePaymentReturnUrl({ origin: 'http://localhost:5174', clientOrigin: 'http://localhost:5174', allowList: '' }),
    ).toBe(`http://localhost:5174${PAYMENT_RETURN_PATH}`);
  });
});
