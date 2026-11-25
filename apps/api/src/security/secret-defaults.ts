import { createHash } from 'crypto';

/**
 * SHA-256 fingerprints of development defaults that must never be used when the
 * API runs outside development.
 *
 * Only digests are stored here on purpose: this file is tracked, and the
 * plaintext values behind these digests are the local development defaults.
 * Add a digest whenever a new placeholder is introduced.
 */
export const KNOWN_DEFAULT_SECRET_SHA256: readonly string[] = [
  'f025a0e7bd1318c13e1ab04e8d3f93d397751167e0f9e194a9e7b1e97ba12a53',
  'a5e0035880bb0594de4afc39c644c959ac63ee365694f980461d7b5f44e9d125',
  '6087bf2dd9453b3873668690a8c129a841f31bc48c6decc09fbf17b8c124be61',
  'e86f78a8a3caf0b60d8e74e5942aa6d86dc150cd3c03338aef25b7d2d7e3acc7',
];

/** Obviously-fake placeholder literals (never secrets). */
export const KNOWN_DEFAULT_SECRET_LITERALS: readonly string[] = [
  'changeme',
  'change-me',
  'change_me',
  'your-256-bit-secret',
  'your-secret-here',
  'secret',
  'password',
  'password123',
  'passw0rd',
  'admin',
  'admin123',
  'admin1234',
  'admin@123',
  'admin@1234',
  'administrator',
  'root',
  'postgres',
  'qwerty',
  'letmein',
  'welcome',
  'default',
  'demo',
  '123456',
  '12345678',
  '123456789',
  'test',
  'dev',
];

export function sha256Hex(value: string): string {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

/** True when [value] is a documented placeholder / known development default. */
export function isKnownDefaultSecret(
  value: string | undefined,
  digests: readonly string[] = KNOWN_DEFAULT_SECRET_SHA256,
): boolean {
  if (!value) return false;
  const normalized = value.trim();
  // Labels written into .env.example, e.g. "CHANGE_ME_...".
  if (normalized.toUpperCase().startsWith('CHANGE_ME')) return true;
  if (KNOWN_DEFAULT_SECRET_LITERALS.includes(normalized.toLowerCase())) return true;
  return digests.includes(sha256Hex(normalized));
}
