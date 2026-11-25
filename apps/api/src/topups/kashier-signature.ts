import { timingSafeEqual } from 'crypto';
import { createHmac } from 'crypto';

/**
 * Kashier webhook signature verification.
 * Docs: https://developers.kashier.io/docs/webhooks#step-4-verify-the-signature
 * Sort `signatureKeys` alphabetically, URL-encode VALUES only (RFC 3986),
 * join `key=value` with `&`, HMAC-SHA256 keyed with the Payment API Key
 * (the `api-key` credential, not the secret key), compare with the
 * `x-kashier-signature` header. Comparison is case-insensitive hex.
 * Docs: https://developers.kashier.io/docs/get-started/api-keys#credentials-at-a-glance
 */
export function rfc3986Encode(value: string): string {
  return encodeURIComponent(value).replace(/[!'()*]/g, (char) => `%${char.charCodeAt(0).toString(16).toUpperCase()}`);
}

export function buildSignaturePayload(data: Record<string, unknown>, signatureKeys: string[]): string {
  const sorted = [...signatureKeys].sort();
  return sorted
    .map((key) => {
      const value = data[key];
      const text = value === null || value === undefined ? '' : String(value);
      return `${key}=${rfc3986Encode(text)}`;
    })
    .join('&');
}

export function verifyKashierSignature(
  data: Record<string, unknown>,
  headerSignature: string | undefined,
  paymentApiKey: string,
): boolean {
  const keys = (data as { signatureKeys?: unknown }).signatureKeys;
  if (!headerSignature || !Array.isArray(keys) || !keys.length || !keys.every((key) => typeof key === 'string')) {
    return false;
  }
  const computed = createHmac('sha256', paymentApiKey).update(buildSignaturePayload(data, keys)).digest('hex');
  const received = headerSignature.trim().toLowerCase();
  const expected = computed.toLowerCase();
  if (received.length !== expected.length) return false;
  try {
    return timingSafeEqual(Buffer.from(received, 'utf8'), Buffer.from(expected, 'utf8'));
  } catch {
    return false;
  }
}
