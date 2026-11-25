import {
  MIN_JWT_SECRET_LENGTH,
  assertSecretsAreNotDefaults,
  findRejectedSecret,
} from './secret-guard';
import { KNOWN_DEFAULT_SECRET_SHA256, isKnownDefaultSecret, sha256Hex } from './secret-defaults';

describe('isKnownDefaultSecret', () => {
  it('matches documented placeholders case-insensitively', () => {
    expect(isKnownDefaultSecret('changeme')).toBe(true);
    expect(isKnownDefaultSecret('Change-Me')).toBe(true);
    expect(isKnownDefaultSecret('  SECRET  ')).toBe(true);
  });

  it('matches .env.example CHANGE_ME labels', () => {
    expect(isKnownDefaultSecret('CHANGE_ME_RANDOM_32_PLUS_CHARS')).toBe(true);
    expect(isKnownDefaultSecret('change_me_something')).toBe(true);
    expect(isKnownDefaultSecret('a_change_me_later_value')).toBe(false);
  });

  it('matches a value by SHA-256 fingerprint', () => {
    const placeholder = 'local-dev-only-default-value';
    expect(isKnownDefaultSecret(placeholder, [sha256Hex(placeholder)])).toBe(true);
    expect(isKnownDefaultSecret(`${placeholder}!`, [sha256Hex(placeholder)])).toBe(false);
  });

  it('rejects empty and unknown strong values', () => {
    expect(isKnownDefaultSecret(undefined)).toBe(false);
    expect(isKnownDefaultSecret('')).toBe(false);
    expect(isKnownDefaultSecret('a-fresh-random-secret-value-0123456789')).toBe(false);
  });

  it('keeps fingerprints opaque', () => {
    expect(KNOWN_DEFAULT_SECRET_SHA256.length).toBeGreaterThan(0);
    for (const digest of KNOWN_DEFAULT_SECRET_SHA256) {
      expect(digest).toMatch(/^[0-9a-f]{64}$/);
    }
  });
});

describe('findRejectedSecret', () => {
  it('names JWT_SECRET when it is a development default', () => {
    expect(findRejectedSecret({ NODE_ENV: 'production', JWT_SECRET: 'changeme' })).toContain('JWT_SECRET');
  });

  it('names ADMIN_PASSWORD when it is a development default', () => {
    expect(findRejectedSecret({ NODE_ENV: 'production', ADMIN_PASSWORD: 'password' })).toContain('ADMIN_PASSWORD');
  });

  it('rejects a too-short signing secret', () => {
    const message = findRejectedSecret({ NODE_ENV: 'production', JWT_SECRET: 'x'.repeat(MIN_JWT_SECRET_LENGTH - 1) });
    expect(message).toContain('shorter than');
    expect(findRejectedSecret({ NODE_ENV: 'production', JWT_SECRET: 'x'.repeat(MIN_JWT_SECRET_LENGTH) })).toBeUndefined();
  });

  it('does not enforce a length floor on ADMIN_PASSWORD', () => {
    expect(findRejectedSecret({ NODE_ENV: 'production', ADMIN_PASSWORD: 'a-brand-new-strong-enough-pw' })).toBeUndefined();
  });

  it('accepts an absent secret instead of failing closed on unset keys', () => {
    expect(findRejectedSecret({ NODE_ENV: 'production' })).toBeUndefined();
  });

  it('accepts a fresh non-default secret', () => {
    expect(
      findRejectedSecret({ NODE_ENV: 'production', JWT_SECRET: 'a-brand-new-64-char-signing-secret-value-here', ADMIN_PASSWORD: 'a-brand-new-admin-pw' }),
    ).toBeUndefined();
  });
});

describe('assertSecretsAreNotDefaults', () => {
  it('refuses to boot outside development with a known default', () => {
    expect(() => assertSecretsAreNotDefaults({ NODE_ENV: 'production', JWT_SECRET: 'changeme' })).toThrow(/Refusing to boot outside development/);
    expect(() => assertSecretsAreNotDefaults({ NODE_ENV: 'staging', ADMIN_PASSWORD: 'test' })).toThrow(/Refusing to boot outside development/);
  });

  it('allows development to run with placeholders', () => {
    expect(() => assertSecretsAreNotDefaults({ NODE_ENV: 'development', JWT_SECRET: 'changeme', ADMIN_PASSWORD: 'password' })).not.toThrow();
  });

  it('allows a production env with a fresh secret', () => {
    expect(() =>
      assertSecretsAreNotDefaults({ NODE_ENV: 'production', JWT_SECRET: 'a-brand-new-64-char-signing-secret-value-here' }),
    ).not.toThrow();
  });
});
