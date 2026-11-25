import { buildSignaturePayload, rfc3986Encode, verifyKashierSignature } from './kashier-signature';

/**
 * Known-answer vector straight from the official docs (illustrative key).
 * Docs: https://developers.kashier.io/docs/webhooks#how-the-signature-is-computed-step-by-step
 */
const DOCS_DATA = {
  amount: 1,
  channel: 'online | e-commerce',
  currency: 'EGP',
  kashierOrderId: '9ad06b17-755b-4e21-9774-aff3e2726ac9',
  merchantOrderId: '1653481557813',
  method: 'card',
  orderReference: 'TEST-ORD-38855',
  status: 'SUCCESS',
  transactionId: 'TX-249893963',
  transactionResponseCode: '00',
  signatureKeys: [
    'amount', 'channel', 'currency', 'kashierOrderId', 'merchantOrderId',
    'method', 'orderReference', 'status', 'transactionId', 'transactionResponseCode',
  ],
};
const DOCS_DIGEST = '9610477b2255b2a8ef84fd89adfaa5f1305ff9c20324205851890f1ea03109f4';

describe('kashier-signature', () => {
  it('reproduces the documented signature payload byte-for-byte', () => {
    expect(buildSignaturePayload(DOCS_DATA, DOCS_DATA.signatureKeys)).toBe(
      'amount=1&channel=online%20%7C%20e-commerce&currency=EGP&kashierOrderId=9ad06b17-755b-4e21-9774-aff3e2726ac9&merchantOrderId=1653481557813&method=card&orderReference=TEST-ORD-38855&status=SUCCESS&transactionId=TX-249893963&transactionResponseCode=00',
    );
  });

  it('verifies the documented digest with the documented illustrative key', () => {
    expect(verifyKashierSignature(DOCS_DATA, DOCS_DIGEST, '11111')).toBe(true);
    // Case-insensitive hex comparison per docs.
    expect(verifyKashierSignature(DOCS_DATA, DOCS_DIGEST.toUpperCase(), '11111')).toBe(true);
  });

  it('rejects tampered payloads, wrong keys, and malformed input', () => {
    expect(verifyKashierSignature({ ...DOCS_DATA, amount: 2 }, DOCS_DIGEST, '11111')).toBe(false);
    expect(verifyKashierSignature(DOCS_DATA, DOCS_DIGEST, 'wrong-key')).toBe(false);
    expect(verifyKashierSignature(DOCS_DATA, undefined, '11111')).toBe(false);
    expect(verifyKashierSignature({ ...DOCS_DATA, signatureKeys: 'amount' }, DOCS_DIGEST, '11111')).toBe(false);
    expect(verifyKashierSignature(DOCS_DATA, 'abcd', '11111')).toBe(false);
  });

  it('encodes values per RFC 3986', () => {
    expect(rfc3986Encode("a b|c!d'e*f(g)h")).toBe('a%20b%7Cc%21d%27e%2Af%28g%29h');
  });
});
