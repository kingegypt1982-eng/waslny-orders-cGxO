import {
  ForbiddenException,
  ServiceUnavailableException,
  UnauthorizedException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { createHmac } from 'crypto';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { buildSignaturePayload } from './kashier-signature';
import { KashierClient } from './kashier.client';
import { PAYMENT_RETURN_PATH } from './payment-return-url';
import { TopUpsService } from './topups.service';

const TEST_API_KEY = 'test-payment-api-key';

function signWebhook(data: Record<string, unknown>): string {
  const keys = data.signatureKeys as string[];
  return createHmac('sha256', TEST_API_KEY).update(buildSignaturePayload(data, keys)).digest('hex');
}

function webhookData(overrides: Record<string, unknown> = {}) {
  return {
    merchantOrderId: 'topup_abc123',
    kashierOrderId: 'kash-1',
    orderReference: 'TEST-1',
    transactionId: 'TX-1',
    status: 'SUCCESS',
    method: 'card',
    channel: 'online',
    amount: 200,
    currency: 'EGP',
    transactionResponseCode: '00',
    signatureKeys: [
      'amount', 'channel', 'currency', 'kashierOrderId', 'merchantOrderId',
      'method', 'orderReference', 'status', 'transactionId', 'transactionResponseCode',
    ],
    ...overrides,
  };
}

describe('TopUpsService (Kashier sandbox, all network mocked)', () => {
  const tx = {
    topUp: { updateMany: jest.fn() },
    wallet: { update: jest.fn() },
    walletTransaction: { create: jest.fn() },
  };
  const prisma = {
    $transaction: jest.fn(async (callback: any) => callback(tx)),
    captainProfile: { findUnique: jest.fn() },
    pricingSettings: { upsert: jest.fn() },
    user: { findUnique: jest.fn() },
    topUp: { create: jest.fn(), update: jest.fn(), findUnique: jest.fn(), findFirst: jest.fn(), updateMany: jest.fn(), findMany: jest.fn() },
    wallet: { update: jest.fn() },
    walletTransaction: { create: jest.fn() },
  };
  const kashier = {
    createSession: jest.fn(),
    getTransactionStatus: jest.fn(),
    getOrderByMerchantRef: jest.fn(),
    verifyWebhook: jest.fn(),
    webhookUrl: 'https://tunnel.test/webhooks/kashier',
    redirectUrl: 'https://app.test/payment-redirect',
  };

  const service = new TopUpsService(
    prisma as unknown as PrismaService,
    kashier as unknown as KashierClient,
  );

  const ENV_KEYS = ['CLIENT_ORIGIN', 'CORS_ORIGINS', 'NODE_ENV'] as const;
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
    jest.clearAllMocks();
    kashier.redirectUrl = 'https://app.test/payment-redirect';
    for (const key of ENV_KEYS) delete process.env[key];
    prisma.$transaction.mockImplementation(async (callback: any) => callback(tx));
    prisma.pricingSettings.upsert.mockResolvedValue({ minTopUpAmount: 50, maxTopUpAmount: 10000, paymentFeePercent: 2.5, paymentFeeFixed: 0 });
    prisma.topUp.findFirst.mockResolvedValue(null);
  });

  function stubPendingTopUp() {
    prisma.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    prisma.user.findUnique.mockResolvedValue({ email: 'cap@test.com' });
    prisma.topUp.create.mockImplementation(async ({ data }: any) => ({ id: 't1', status: 'PENDING', ...data }));
    kashier.createSession.mockResolvedValue({ sessionId: 'sess-1', checkoutUrl: 'https://pay.test/sess-1' });
  }

  it('creates a PENDING top-up and returns the checkout URL and id', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    prisma.user.findUnique.mockResolvedValue({ email: 'cap@test.com' });
    prisma.topUp.create.mockImplementation(async ({ data }: any) => ({ id: 't1', status: 'PENDING', ...data }));
    kashier.createSession.mockResolvedValue({ sessionId: 'sess-1', checkoutUrl: 'https://pay.test/sess-1' });

    // 200 credit at 2.5% + 0 fixed -> 200 / 0.975 = 205.128... -> charge 205.13
    const result = await service.createTopUp('cap1', 200);

    expect(result).toEqual({ topUpId: 't1', checkoutUrl: 'https://pay.test/sess-1', creditAmount: 200, chargeAmount: 205.13, feeAmount: 5.13 });
    expect(kashier.createSession).toHaveBeenCalledWith({
      amount: '205.13',
      currency: 'EGP',
      orderRef: expect.stringMatching(/^topup_[0-9a-f]{32}$/),
      description: expect.stringContaining('topup_'),
      redirectUrl: 'https://app.test/payment-redirect',
      customer: { email: 'cap@test.com', reference: 'cap1' },
    });
    expect(prisma.topUp.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        userId: 'cap1', amount: 200, providerOrderRef: expect.any(String),
        feePercent: 2.5, feeFixed: 0,
      }),
    });
    const stored = prisma.topUp.create.mock.calls[0][0].data;
    expect(stored.creditAmount.toFixed(2)).toBe('200.00');
    expect(stored.chargeAmount.toFixed(2)).toBe('205.13');
    expect(stored.feeAmount.toFixed(2)).toBe('5.13');
  });

  it('prefers the configured .env return URL verbatim over the request origin', async () => {
    stubPendingTopUp();
    process.env.CORS_ORIGINS = 'http://localhost:5173';
    kashier.redirectUrl = 'https://tunnel.test/api/v1/payment-return';

    await service.createTopUp('cap1', 200, 'http://localhost:5173');

    expect(kashier.createSession).toHaveBeenCalledWith(
      expect.objectContaining({ redirectUrl: 'https://tunnel.test/api/v1/payment-return' }),
    );
  });

  it('sends the payer to the API return page on the allow-listed request origin', async () => {
    stubPendingTopUp();
    kashier.redirectUrl = '';
    process.env.CORS_ORIGINS = 'http://localhost:5173,http://localhost:5174';

    await service.createTopUp('cap1', 200, 'http://localhost:5173');

    expect(kashier.createSession).toHaveBeenCalledWith(
      expect.objectContaining({ redirectUrl: `http://localhost:5173${PAYMENT_RETURN_PATH}` }),
    );
  });

  it('ignores an Origin outside the allow-list and uses CLIENT_ORIGIN', async () => {
    stubPendingTopUp();
    kashier.redirectUrl = '';
    process.env.CORS_ORIGINS = 'http://localhost:5173';
    process.env.CLIENT_ORIGIN = 'http://localhost:5173';

    await service.createTopUp('cap1', 200, 'https://evil.example/phish?next=1');

    expect(kashier.createSession).toHaveBeenCalledWith(
      expect.objectContaining({ redirectUrl: `http://localhost:5173${PAYMENT_RETURN_PATH}` }),
    );
  });

  it('rejects a custom-scheme return URL before creating a top-up', async () => {
    stubPendingTopUp();
    kashier.redirectUrl = 'myapp://wallet/topup-result';

    await expect(service.createTopUp('cap1', 200)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(prisma.topUp.create).not.toHaveBeenCalled();
    expect(kashier.createSession).not.toHaveBeenCalled();
  });

  it('reuses a recent PENDING top-up instead of creating a duplicate', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    prisma.topUp.findFirst.mockResolvedValue({
      id: 'existing',
      creditAmount: new Prisma.Decimal('200.00'),
      chargeAmount: new Prisma.Decimal('205.13'),
      feeAmount: new Prisma.Decimal('5.13'),
      checkoutUrl: 'https://pay.test/existing',
    });

    const result = await service.createTopUp('cap1', 200);

    expect(result).toEqual({
      topUpId: 'existing',
      checkoutUrl: 'https://pay.test/existing',
      creditAmount: 200,
      chargeAmount: 205.13,
      feeAmount: 5.13,
    });
    expect(prisma.topUp.create).not.toHaveBeenCalled();
    expect(kashier.createSession).not.toHaveBeenCalled();
  });

  it('simulates a development success only once for a pending top-up', async () => {
    process.env.NODE_ENV = 'development';
    prisma.topUp.findUnique
      .mockResolvedValueOnce({ ...pendingTopUp })
      .mockResolvedValueOnce({ ...pendingTopUp, status: 'SUCCEEDED' });
    tx.topUp.updateMany.mockResolvedValue({ count: 1 });

    const first = await service.simulateDevelopmentSuccess('cap1', 't1');
    const replay = await service.simulateDevelopmentSuccess('cap1', 't1');

    expect(first).toEqual({ status: 'SUCCEEDED', credited: true });
    expect(replay).toEqual({ status: 'SUCCEEDED', credited: false });
    expect(tx.wallet.update).toHaveBeenCalledTimes(1);
    expect(tx.walletTransaction.create).toHaveBeenCalledTimes(1);
    expect(tx.topUp.updateMany).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ providerTransactionId: 'development_t1' }),
    }));
  });

  it.each([undefined, 'test', 'production'])(
    'disables development top-up simulation when NODE_ENV is %s',
    async (nodeEnv) => {
      if (nodeEnv) process.env.NODE_ENV = nodeEnv;

      await expect(service.simulateDevelopmentSuccess('cap1', 't1')).rejects.toBeInstanceOf(
        ForbiddenException,
      );
      expect(prisma.topUp.findUnique).not.toHaveBeenCalled();
    },
  );

  it('rejects amounts outside the admin-configured limits', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });

    await expect(service.createTopUp('cap1', 10)).rejects.toBeInstanceOf(UnprocessableEntityException);
    await expect(service.createTopUp('cap1', 50000)).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(prisma.topUp.create).not.toHaveBeenCalled();
    expect(kashier.createSession).not.toHaveBeenCalled();
  });

  it('rejects non-captains and unapproved captains', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue(null);
    await expect(service.createTopUp('x', 200)).rejects.toBeInstanceOf(ForbiddenException);

    prisma.captainProfile.findUnique.mockResolvedValue({ status: 'PENDING' });
    await expect(service.createTopUp('x', 200)).rejects.toBeInstanceOf(ForbiddenException);
    expect(kashier.createSession).not.toHaveBeenCalled();
  });

  it('marks the top-up FAILED when Kashier is unreachable', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    prisma.topUp.create.mockImplementation(async ({ data }: any) => ({ id: 't1', status: 'PENDING', ...data }));
    kashier.createSession.mockRejectedValue(new Error('socket hangup'));

    await expect(service.createTopUp('cap1', 200)).rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(prisma.topUp.update).toHaveBeenCalledWith({
      where: { id: 't1' },
      data: expect.objectContaining({ status: 'FAILED' }),
    });
  });

  it('rejects webhooks with an invalid signature before any processing', async () => {
    kashier.verifyWebhook.mockReturnValue(false);

    await expect(service.handleWebhook('bogus', { data: webhookData() })).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(prisma.topUp.findUnique).not.toHaveBeenCalled();
  });

  const pendingTopUp = { id: 't1', userId: 'cap1', amount: 200, creditAmount: 200, chargeAmount: 200, feeAmount: 0, feePercent: 2.5, feeFixed: 0, currency: 'EGP', status: 'PENDING', providerOrderRef: 'topup_abc123' };

  function validSetup() {
    kashier.verifyWebhook.mockReturnValue(true);
    prisma.topUp.findUnique.mockResolvedValue({ ...pendingTopUp });
    kashier.getTransactionStatus.mockResolvedValue({ status: 'SUCCESS' });
    tx.topUp.updateMany.mockResolvedValue({ count: 1 });
  }

  it('credits the wallet exactly once on a successful webhook', async () => {
    validSetup();

    const first = await service.handleWebhook('sig', { data: webhookData() });
    expect(first).toEqual({ acknowledged: true });
    expect(tx.wallet.update).toHaveBeenCalledWith({
      where: { userId: 'cap1' },
      data: { balance: { increment: expect.anything() } },
    });
    expect(tx.walletTransaction.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ userId: 'cap1', topUpId: 't1', type: 'TOP_UP' }),
    });

    // Replay of the same event: the TopUp is SUCCEEDED now, nothing moves.
    jest.clearAllMocks();
    prisma.topUp.findUnique.mockResolvedValue({ ...pendingTopUp, status: 'SUCCEEDED' });

    const second = await service.handleWebhook('sig', { data: webhookData() });
    expect(second).toEqual({ acknowledged: true });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('credits creditAmount (not chargeAmount) on a grossed-up webhook', async () => {
    const grossed = {
      ...pendingTopUp, amount: 100, creditAmount: 100, chargeAmount: 102.56, feeAmount: 2.56,
    };
    kashier.verifyWebhook.mockReturnValue(true);
    prisma.topUp.findUnique.mockResolvedValue(grossed);
    kashier.getTransactionStatus.mockResolvedValue({ status: 'SUCCESS' });
    tx.topUp.updateMany.mockResolvedValue({ count: 1 });

    await service.handleWebhook('sig', { data: webhookData({ amount: 102.56 }) });

    const increment = tx.wallet.update.mock.calls[0][0].data.balance.increment;
    expect(increment.toFixed(2)).toBe('100.00');
    const ledger = tx.walletTransaction.create.mock.calls[0][0].data;
    expect(ledger.amount.toFixed(2)).toBe('100.00');
    expect(ledger.note).toMatch(/after fees/);
  });

  it('rejects a webhook carrying the credit amount instead of the charge', async () => {
    const grossed = {
      ...pendingTopUp, amount: 100, creditAmount: 100, chargeAmount: 102.56, feeAmount: 2.56,
    };
    kashier.verifyWebhook.mockReturnValue(true);
    prisma.topUp.findUnique.mockResolvedValue(grossed);

    await service.handleWebhook('sig', { data: webhookData({ amount: 100 }) });

    expect(prisma.topUp.update).toHaveBeenCalledWith({
      where: { id: 't1' },
      data: expect.objectContaining({ status: 'FAILED' }),
    });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('ignores later fee-setting edits for an existing TopUp', async () => {
    // Admin raised the fee to 5% + 10 fixed AFTER this TopUp was created.
    prisma.pricingSettings.upsert.mockResolvedValue({ minTopUpAmount: 50, maxTopUpAmount: 10000, paymentFeePercent: 5, paymentFeeFixed: 10 });
    kashier.verifyWebhook.mockReturnValue(true);
    prisma.topUp.findUnique.mockResolvedValue({ ...pendingTopUp });
    kashier.getTransactionStatus.mockResolvedValue({ status: 'SUCCESS' });
    tx.topUp.updateMany.mockResolvedValue({ count: 1 });

    await service.handleWebhook('sig', { data: webhookData() });

    // Stored snapshot (2.5%/0 -> charge 200) still governs, not the new 5%/10.
    expect(tx.wallet.update).toHaveBeenCalledTimes(1);
  });

  it('lets exactly one of two concurrent deliveries win', async () => {
    validSetup();
    tx.topUp.updateMany.mockResolvedValueOnce({ count: 1 }).mockResolvedValueOnce({ count: 0 });

    await service.handleWebhook('sig', { data: webhookData() });
    await service.handleWebhook('sig', { data: webhookData() });

    expect(tx.wallet.update).toHaveBeenCalledTimes(1);
    expect(tx.walletTransaction.create).toHaveBeenCalledTimes(1);
  });

  it('fails top-ups on amount or currency mismatch without crediting', async () => {
    kashier.verifyWebhook.mockReturnValue(true);
    prisma.topUp.findUnique.mockResolvedValue({ ...pendingTopUp });

    // Minor-units style value against a major-units record must mismatch.
    await service.handleWebhook('sig', { data: webhookData({ amount: 20000 }) });
    expect(prisma.topUp.update).toHaveBeenCalledWith({
      where: { id: 't1' },
      data: expect.objectContaining({ status: 'FAILED' }),
    });
    expect(prisma.$transaction).not.toHaveBeenCalled();

    jest.clearAllMocks();
    prisma.topUp.findUnique.mockResolvedValue({ ...pendingTopUp });
    await service.handleWebhook('sig', { data: webhookData({ currency: 'USD' }) });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('credits 50 against "50.00" exactly once (major units)', async () => {
    kashier.verifyWebhook.mockReturnValue(true);
    prisma.topUp.findUnique.mockResolvedValue({ ...pendingTopUp, amount: 50, creditAmount: 50, chargeAmount: 50 });
    kashier.getTransactionStatus.mockResolvedValue({ status: 'SUCCESS' });
    tx.topUp.updateMany.mockResolvedValue({ count: 1 });

    await service.handleWebhook('sig', { data: webhookData({ amount: '50.00' }) });

    expect(tx.wallet.update).toHaveBeenCalledTimes(1);
    expect(tx.walletTransaction.create).toHaveBeenCalledTimes(1);
  });

  it('reprocesses a mismatch-FAILED top-up exactly once, then ignores resends', async () => {
    const mismatchFailed = { ...pendingTopUp, status: 'FAILED', failureReason: 'Amount or currency mismatch' };
    kashier.verifyWebhook.mockReturnValue(true);
    prisma.topUp.findUnique
      .mockResolvedValueOnce(mismatchFailed)
      .mockResolvedValueOnce({ ...mismatchFailed, status: 'SUCCEEDED' });
    kashier.getTransactionStatus.mockResolvedValue({ status: 'SUCCESS' });
    tx.topUp.updateMany.mockResolvedValue({ count: 1 });

    expect(await service.handleWebhook('sig', { data: webhookData() })).toEqual({ acknowledged: true });
    expect(tx.wallet.update).toHaveBeenCalledTimes(1);

    expect(await service.handleWebhook('sig', { data: webhookData() })).toEqual({ acknowledged: true });
    expect(tx.wallet.update).toHaveBeenCalledTimes(1);
  });

  it('never reprocesses a FAILED top-up with another reason', async () => {
    kashier.verifyWebhook.mockReturnValue(true);
    prisma.topUp.findUnique.mockResolvedValue({
      ...pendingTopUp, status: 'FAILED', failureReason: 'Kashier reported FAILURE',
    });

    expect(await service.handleWebhook('sig', { data: webhookData() })).toEqual({ acknowledged: true });
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(prisma.topUp.update).not.toHaveBeenCalled();
  });

  it('logs outcomes without any key material', async () => {
    const logs: string[] = [];
    (service as any).logger = {
      log: jest.fn((m: string) => logs.push(m)),
      warn: jest.fn((m: string) => logs.push(m)),
      error: jest.fn((m: string) => logs.push(m)),
    };
    kashier.verifyWebhook.mockReturnValue(true);
    prisma.topUp.findUnique.mockResolvedValue({ ...pendingTopUp });
    kashier.getTransactionStatus.mockResolvedValue({ status: 'SUCCESS' });
    tx.topUp.updateMany.mockResolvedValue({ count: 1 });

    await service.handleWebhook('real-signature-hex', { data: webhookData() });
    kashier.verifyWebhook.mockReturnValue(false);
    await expect(service.handleWebhook('bogus-hex', { data: webhookData() })).rejects.toThrow();

    const blob = logs.join('\n');
    expect(logs.length).toBeGreaterThan(0);
    expect(blob).not.toMatch(/test-payment-api-key|test-secret|real-signature-hex|bogus-hex|TX-1/);
    expect(blob).toMatch(/topup_abc123/);
  });

  it('acks unknown references without any writes', async () => {
    kashier.verifyWebhook.mockReturnValue(true);
    prisma.topUp.findUnique.mockResolvedValue(null);

    expect(await service.handleWebhook('sig', { data: webhookData() })).toEqual({ acknowledged: true });
    expect(prisma.topUp.update).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('marks failed payments FAILED and keeps pending ones untouched', async () => {
    kashier.verifyWebhook.mockReturnValue(true);
    prisma.topUp.findUnique.mockResolvedValue({ ...pendingTopUp });

    await service.handleWebhook('sig', { data: webhookData({ status: 'FAILURE' }) });
    expect(prisma.topUp.update).toHaveBeenCalledWith({
      where: { id: 't1' },
      data: expect.objectContaining({ status: 'FAILED' }),
    });
    expect(prisma.$transaction).not.toHaveBeenCalled();

    jest.clearAllMocks();
    prisma.topUp.findUnique.mockResolvedValue({ ...pendingTopUp });
    await service.handleWebhook('sig', { data: webhookData({ status: 'PENDING' }) });
    expect(prisma.topUp.update).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('stays PENDING when the confirmation inquiry is unreachable', async () => {
    kashier.verifyWebhook.mockReturnValue(true);
    prisma.topUp.findUnique.mockResolvedValue({ ...pendingTopUp });
    kashier.getTransactionStatus.mockRejectedValue(new Error('timeout'));

    expect(await service.handleWebhook('sig', { data: webhookData() })).toEqual({ acknowledged: true });
    expect(prisma.topUp.update).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('enforces ownership on top-up reads', async () => {
    prisma.topUp.findUnique.mockResolvedValue({ ...pendingTopUp });

    await expect(service.getTopUp('stranger', 't1')).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.getTopUp('cap1', 't1')).resolves.toMatchObject({ id: 't1' });
  });

  it('exposes no redirect-crediting path and no key material', async () => {
    const proto = Object.getOwnPropertyNames(TopUpsService.prototype);
    expect(proto.some((name) => /redirect/i.test(name))).toBe(false);

    prisma.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    prisma.topUp.create.mockImplementation(async ({ data }: any) => ({ id: 't1', status: 'PENDING', ...data }));
    kashier.createSession.mockResolvedValue({ sessionId: 'sess-1', checkoutUrl: 'https://pay.test/sess-1' });

    const result = await service.createTopUp('cap1', 200);
    expect(Object.keys(result).sort()).toEqual([
      'chargeAmount', 'checkoutUrl', 'creditAmount', 'feeAmount', 'topUpId',
    ]);
  });

  it('uses the real signature path end to end', async () => {
    const real = new TopUpsService(
      prisma as unknown as PrismaService,
      new KashierClient({
        baseUrl: 'https://test-api.kashier.io',
        merchantId: 'MID-TEST',
        apiKey: TEST_API_KEY,
        secretKey: 'test-secret',
        redirectUrl: 'myapp://x',
      }),
    );
    const data = webhookData();
    const signature = signWebhook(data);

    prisma.topUp.findUnique.mockResolvedValue(null);
    await expect(real.handleWebhook(signature, { data })).resolves.toEqual({ acknowledged: true });

    await expect(real.handleWebhook('00', { data })).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('leaves the TopUp PENDING when the inquiry reports an intermediate status', async () => {
    kashier.verifyWebhook.mockReturnValue(true);
    prisma.topUp.findUnique.mockResolvedValue({ ...pendingTopUp });
    kashier.getTransactionStatus.mockResolvedValue({ status: 'PENDING' });

    expect(await service.handleWebhook('sig', { data: webhookData() })).toEqual({ acknowledged: true });
    expect(prisma.topUp.update).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  const reconRow = (overrides: Record<string, unknown> = {}) => ({
    id: 't1', userId: 'cap1', amount: 200, creditAmount: 200, chargeAmount: 200,
    feeAmount: 0, feePercent: 2.5, feeFixed: 0, currency: 'EGP', status: 'PENDING',
    providerOrderRef: 'topup_abc123', createdAt: new Date(Date.now() - 60_000), ...overrides,
  });
  const payTxn = (overrides: Record<string, unknown> = {}) => ({
    transactionId: 'TX-9', status: 'SUCCESS', amount: 200, currency: 'EGP', ...overrides,
  });

  it('reconciler credits a confirmed SUCCESS exactly once', async () => {
    prisma.topUp.findMany.mockResolvedValue([reconRow()]);
    kashier.getOrderByMerchantRef.mockResolvedValue({ found: true, payTransactions: [payTxn()] });
    tx.topUp.updateMany.mockResolvedValue({ count: 1 });

    const result = await service.reconcilePendingBatch(new Date());

    expect(result).toEqual({ checked: 1, charged: 1 });
    expect(tx.wallet.update).toHaveBeenCalledTimes(1);
    const increment = tx.wallet.update.mock.calls[0][0].data.balance.increment;
    expect(increment.toFixed(2)).toBe('200.00');
  });

  it('webhook and reconciler racing still credit only once', async () => {
    kashier.verifyWebhook.mockReturnValue(true);
    prisma.topUp.findUnique.mockResolvedValue({ ...pendingTopUp });
    prisma.topUp.findMany.mockResolvedValue([reconRow()]);
    kashier.getTransactionStatus.mockResolvedValue({ status: 'SUCCESS' });
    kashier.getOrderByMerchantRef.mockResolvedValue({ found: true, payTransactions: [payTxn()] });
    tx.topUp.updateMany.mockResolvedValueOnce({ count: 1 }).mockResolvedValueOnce({ count: 0 });

    await service.handleWebhook('sig', { data: webhookData() });
    await service.reconcilePendingBatch(new Date());

    expect(tx.wallet.update).toHaveBeenCalledTimes(1);
    expect(tx.walletTransaction.create).toHaveBeenCalledTimes(1);
  });

  it('reconciler marks terminal FAILURE without crediting', async () => {
    prisma.topUp.findMany.mockResolvedValue([reconRow()]);
    kashier.getOrderByMerchantRef.mockResolvedValue({ found: true, payTransactions: [payTxn({ status: 'FAILURE' })] });

    const result = await service.reconcilePendingBatch(new Date());

    expect(result).toEqual({ checked: 1, charged: 0 });
    expect(prisma.topUp.update).toHaveBeenCalledWith({
      where: { id: 't1' },
      data: expect.objectContaining({ status: 'FAILED' }),
    });
    expect(tx.wallet.update).not.toHaveBeenCalled();
  });

  it('reconciler recovers an unconfirmed-FAILED row once, then ignores it', async () => {
    const frozen = reconRow({ status: 'FAILED', failureReason: 'Transaction not confirmed successful' });
    prisma.topUp.findMany.mockResolvedValueOnce([frozen]).mockResolvedValueOnce([]);
    kashier.getOrderByMerchantRef.mockResolvedValue({ found: true, payTransactions: [payTxn()] });
    tx.topUp.updateMany.mockResolvedValue({ count: 1 });

    expect(await service.reconcilePendingBatch(new Date())).toEqual({ checked: 1, charged: 1 });
    expect(await service.reconcilePendingBatch(new Date())).toEqual({ checked: 0, charged: 0 });
    expect(tx.wallet.update).toHaveBeenCalledTimes(1);
  });

  it('reconciler never touches FAILED rows with other reasons', async () => {
    prisma.topUp.findMany.mockResolvedValue([]);

    await service.reconcilePendingBatch(new Date());

    const where = prisma.topUp.findMany.mock.calls[0][0].where;
    const failedBranch = where.OR.find((b: any) => b.status === 'FAILED');
    expect(failedBranch.failureReason).toBe('Transaction not confirmed successful');
  });

  it('reconciler rejects mismatched amounts without crediting', async () => {
    prisma.topUp.findMany.mockResolvedValue([reconRow()]);
    kashier.getOrderByMerchantRef.mockResolvedValue({ found: true, payTransactions: [payTxn({ amount: 999 })] });

    const result = await service.reconcilePendingBatch(new Date());

    expect(result).toEqual({ checked: 1, charged: 0 });
    expect(tx.wallet.update).not.toHaveBeenCalled();
  });

  it('reconciler selects the documented age window with a bounded batch', async () => {
    prisma.topUp.findMany.mockResolvedValue([]);
    const now = new Date('2026-10-10T12:00:00Z');

    await service.reconcilePendingBatch(now);

    const where = prisma.topUp.findMany.mock.calls[0][0].where;
    const pending = where.OR.find((b: any) => b.status === 'PENDING');
    expect(new Date(pending.createdAt.gt).getTime()).toBe(now.getTime() - 60 * 60_000);
    expect(new Date(pending.createdAt.lt).getTime()).toBe(now.getTime() - 30_000);
    const failed = where.OR.find((b: any) => b.status === 'FAILED');
    expect(new Date(failed.createdAt.gt).getTime()).toBe(now.getTime() - 7 * 24 * 60 * 60_000);
    expect(prisma.topUp.findMany.mock.calls[0][0].take).toBe(20);
  });
});
