import { KashierClient } from './kashier.client';

const CONFIG = {
  baseUrl: 'https://test-api.kashier.io',
  merchantId: 'MID-TEST-1',
  apiKey: 'test-payment-api-key',
  secretKey: 'test-secret-key',
  redirectUrl: 'myapp://wallet/topup-result',
  webhookUrl: 'https://tunnel.test/webhooks/kashier',
};

describe('KashierClient (network mocked)', () => {
  const realFetch = global.fetch;

  beforeEach(() => {
    global.fetch = jest.fn();
  });

  afterEach(() => {
    global.fetch = realFetch;
  });

  it('creates sessions against the test host with the documented headers', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      json: async () => ({ data: { sessionUrl: 'https://pay.test/s/1', sessionId: 'sess-1' } }),
    });
    const client = new KashierClient(CONFIG);

    const session = await client.createSession({ amount: '200.00', currency: 'EGP', orderRef: 'topup_x', description: 'd' });

    expect(session).toEqual({ sessionId: 'sess-1', checkoutUrl: 'https://pay.test/s/1' });
    const [url, init] = (global.fetch as jest.Mock).mock.calls[0];
    expect(url).toBe('https://test-api.kashier.io/v3/payment/sessions');
    expect(init.method).toBe('POST');
    expect(init.headers).toMatchObject({ Authorization: 'test-secret-key', 'api-key': 'test-payment-api-key' });
    const body = JSON.parse(init.body as string);
    expect(body).toMatchObject({
      amount: '200.00', currency: 'EGP', order: 'topup_x',
      merchantId: 'MID-TEST-1', merchantRedirect: 'myapp://wallet/topup-result',
      serverWebhook: 'https://tunnel.test/webhooks/kashier',
    });
  });

  it('fails closed when the session response has no checkout URL', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({ ok: true, json: async () => ({ data: {} }) });

    await expect(
      new KashierClient(CONFIG).createSession({ amount: '200.00', currency: 'EGP', orderRef: 'x', description: 'd' }),
    ).rejects.toThrow();
  });

  it('queries transaction status with the secret header only', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({ ok: true, json: async () => ({ data: { status: 'SUCCESS' } }) });

    const result = await new KashierClient(CONFIG).getTransactionStatus('TX-1');

    expect(result).toEqual({ status: 'SUCCESS' });
    const [url, init] = (global.fetch as jest.Mock).mock.calls[0];
    expect(url).toBe('https://test-api.kashier.io/v2/aggregator/transactions/TX-1');
    expect(init.headers).toMatchObject({ Authorization: 'test-secret-key' });
  });
});
