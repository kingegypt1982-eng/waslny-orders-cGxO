import { isKnownDefaultSecret } from './secret-defaults';

/** Shortest acceptable signing secret outside development. */
export const MIN_JWT_SECRET_LENGTH = 32;

/** Credential keys that may never carry a development default off-development. */
export const GUARDED_SECRET_KEYS = ['JWT_SECRET', 'ADMIN_PASSWORD'] as const;

export interface EnvLike {
  [key: string]: string | undefined;
}

/** Returns a message naming the offending key, or undefined when the env is acceptable. */
export function findRejectedSecret(env: EnvLike): string | undefined {
  for (const key of GUARDED_SECRET_KEYS) {
    const value = env[key];
    if (!value) continue;
    if (isKnownDefaultSecret(value)) {
      return `${key} is set to a known development default / placeholder`;
    }
  }
  const jwt = env.JWT_SECRET?.trim();
  if (jwt && jwt.length < MIN_JWT_SECRET_LENGTH) {
    return `JWT_SECRET is shorter than ${MIN_JWT_SECRET_LENGTH} characters`;
  }
  return undefined;
}

/**
 * Refuses to boot when a guarded secret is a known development default.
 * Development is explicitly allowed to run with placeholders.
 */
export function assertSecretsAreNotDefaults(env: EnvLike = process.env): void {
  if (env.NODE_ENV === 'development') return;
  const problem = findRejectedSecret(env);
  if (problem) {
    throw new Error(`${problem}. Refusing to boot outside development.`);
  }
}
