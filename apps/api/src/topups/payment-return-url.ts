/**
 * One public API page handles every post-payment return, so a single tunnel can
 * serve both the Kashier webhook and the browser redirect. It is served under
 * the global `/api/v1` prefix as `/api/v1/payment-return`.
 */
export const PAYMENT_RETURN_PATH = '/api/v1/payment-return';

interface ParsedHttpUrl {
  /** Trimmed input, kept verbatim (path, query and fragment included). */
  raw: string;
  url: URL;
}

/** Parses an http(s) URL. Credential-bearing and non-http URLs are rejected. */
function parseHttpUrl(value: string | undefined | null): ParsedHttpUrl | null {
  if (!value) return null;
  const raw = value.trim();
  if (!raw) return null;
  try {
    const url = new URL(raw);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
    if (url.username || url.password) return null;
    return { raw, url };
  } catch {
    return null;
  }
}

/** Parses an http(s) origin. Anything else (custom schemes, garbage) -> null. */
export function parseHttpOrigin(value: string | undefined | null): string | null {
  return parseHttpUrl(value)?.url.origin ?? null;
}

/** Normalises a comma-separated list (Chrome-style CORS list) into origins. */
export function parseOriginList(...values: Array<string | undefined | null>): string[] {
  const origins = new Set<string>();
  for (const value of values) {
    for (const entry of (value ?? '').split(',')) {
      const origin = parseHttpOrigin(entry);
      if (origin) origins.add(origin);
    }
  }
  return [...origins];
}

export interface PaymentReturnInput {
  /** `Origin` header of the request that created the top-up. */
  origin?: string;
  /** Configured app origin, e.g. CLIENT_ORIGIN. */
  clientOrigin?: string;
  /** Configured page URL, e.g. KASHIER_REDIRECT_URL from .env. */
  configuredRedirectUrl?: string;
  /** Comma-separated allow-list; defaults to CORS_ORIGINS. */
  allowList?: string;
}

/**
 * URL the payer's browser returns to after paying.
 *
 * Resolution order:
 *  1. KASHIER_REDIRECT_URL (from .env, or an explicit test value), used
 *     **verbatim** when it is a valid http(s) URL — this is the operator-owned
 *     tunnel URL, including its path/query if any;
 *  2. the request Origin, but only when it is allow-listed (no open redirect);
 *  3. the configured CLIENT_ORIGIN.
 *
 * Fallbacks point at the API's own public page so a single tunnel serves both
 * webhook and return. Only `origin` is ever reused from a request, so a crafted
 * `Origin` cannot smuggle a path or query string into the redirect.
 * Returns null when no http(s) candidate exists.
 */
export function resolvePaymentReturnUrl(input: PaymentReturnInput): string | null {
  const configured = parseHttpUrl(
    input.configuredRedirectUrl ?? process.env.KASHIER_REDIRECT_URL,
  );
  if (configured) return configured.raw;

  const allowList = parseOriginList(
    input.allowList ?? process.env.CORS_ORIGINS,
    input.clientOrigin ?? process.env.CLIENT_ORIGIN,
  );

  const requestOrigin = parseHttpOrigin(input.origin);
  if (requestOrigin && allowList.includes(requestOrigin)) {
    return `${requestOrigin}${PAYMENT_RETURN_PATH}`;
  }

  const clientOrigin = parseHttpOrigin(input.clientOrigin ?? process.env.CLIENT_ORIGIN);
  if (clientOrigin) return `${clientOrigin}${PAYMENT_RETURN_PATH}`;

  return null;
}
