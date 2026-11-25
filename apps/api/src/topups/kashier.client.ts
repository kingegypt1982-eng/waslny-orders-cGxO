import { verifyKashierSignature } from './kashier-signature';

export interface KashierConfig {
  baseUrl: string;
  merchantId: string;
  apiKey: string;
  secretKey: string;
  redirectUrl: string;
  webhookUrl?: string;
}

export interface KashierSession {
  sessionId: string | null;
  checkoutUrl: string;
}

export interface KashierPayTransaction {
  transactionId: string;
  status: string | null;
  amount: unknown;
  currency: unknown;
}

/**
 * Minimal Kashier test-environment client (no SDK).
 * Session creation: https://developers.kashier.io/docs/accept-payments/payment-sessions#step-1-create-a-payment-session
 * Result inquiry:   https://developers.kashier.io/docs/accept-payments/payment-sessions#step-3-verify-the-result
 * Transaction lookup:https://developers.kashier.io/docs/accept-payments/transactions#get-transaction-details
 * Keys are never logged; errors carry HTTP status only.
 */
export class KashierClient {
  constructor(private readonly config: KashierConfig) {}

  static fromEnv(): KashierClient {
    const required = ['KASHIER_BASE_URL', 'KASHIER_MERCHANT_ID', 'KASHIER_API_KEY', 'KASHIER_SECRET_KEY', 'KASHIER_REDIRECT_URL'] as const;
    for (const key of required) {
      if (!process.env[key]) throw new Error(`${key} is not set. Refusing to init Kashier client.`);
    }
    return new KashierClient({
      baseUrl: process.env.KASHIER_BASE_URL as string,
      merchantId: process.env.KASHIER_MERCHANT_ID as string,
      apiKey: process.env.KASHIER_API_KEY as string,
      secretKey: process.env.KASHIER_SECRET_KEY as string,
      redirectUrl: process.env.KASHIER_REDIRECT_URL as string,
      webhookUrl: process.env.KASHIER_WEBHOOK_URL || undefined,
    });
  }

  verifyWebhook(data: Record<string, unknown>, headerSignature: string | undefined): boolean {
    return verifyKashierSignature(data, headerSignature, this.config.apiKey);
  }

  get webhookUrl(): string | undefined {
    return this.config.webhookUrl;
  }

  get redirectUrl(): string {
    return this.config.redirectUrl;
  }

  async createSession(input: {
    amount: string;
    currency: string;
    orderRef: string;
    description: string;
    /** Per-request return URL; falls back to the configured one. */
    redirectUrl?: string;
    customer?: { email?: string; reference?: string };
  }): Promise<KashierSession> {
    const body: Record<string, unknown> = {
      amount: input.amount,
      currency: input.currency,
      order: input.orderRef,
      merchantId: this.config.merchantId,
      merchantRedirect: input.redirectUrl ?? this.config.redirectUrl,
      description: input.description,
      type: 'one-time',
    };
    if (input.customer) body.customer = input.customer;
    // Per-request destination: this payment's events also go here without
    // becoming a configured webhook.
    // Docs: https://developers.kashier.io/docs/webhooks#step-2-point-kashier-at-your-endpoint
    if (this.config.webhookUrl) body.serverWebhook = this.config.webhookUrl;
    const response = await fetch(`${this.config.baseUrl}/v3/payment/sessions`, {
      method: 'POST',
      headers: {
        Authorization: this.config.secretKey,
        'api-key': this.config.apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) throw new Error(`Kashier session request failed (${response.status})`);
    const json = (await response.json()) as Record<string, unknown>;
    const data = (json?.data ?? json) as Record<string, unknown>;
    const checkoutUrl = data?.sessionUrl;
    if (typeof checkoutUrl !== 'string' || !checkoutUrl) {
      throw new Error('Kashier session response missing checkout URL');
    }
    const sessionId = data?.sessionId ?? data?.id ?? data?._id ?? null;
    return { sessionId: typeof sessionId === 'string' ? sessionId : null, checkoutUrl };
  }

  /** Stored transaction status (SUCCESS / FAILURE / PENDING vocabulary). */
  async getTransactionStatus(transactionId: string): Promise<{ status: string | null }> {
    const response = await fetch(
      `${this.config.baseUrl}/v2/aggregator/transactions/${encodeURIComponent(transactionId)}`,
      { headers: { Authorization: this.config.secretKey }, signal: AbortSignal.timeout(15_000) },
    );
    if (!response.ok) {
      const error = new Error(`Kashier inquiry failed (${response.status})`);
      (error as { httpStatus?: number }).httpStatus = response.status;
      throw error;
    }
    const json = (await response.json()) as Record<string, unknown>;
    const data = (json?.data ?? json) as Record<string, unknown>;
    const status = data?.status ?? (json as Record<string, unknown>)?.status ?? null;
    return { status: typeof status === 'string' ? status : null };
  }

  /**
   * Read-only order lookup for the periodic reconciler: finds the order by our
   * merchant reference and returns its `pay` operations.
   * Docs: https://developers.kashier.io/docs/accept-payments/order-reconciliation#retrieve-order-details
   */
  async getOrderByMerchantRef(ref: string): Promise<{ found: boolean; payTransactions: KashierPayTransaction[] }> {
    const response = await fetch(
      `${this.config.baseUrl}/v3/payment/orders?search=${encodeURIComponent(ref)}`,
      { headers: { Authorization: this.config.secretKey }, signal: AbortSignal.timeout(15_000) },
    );
    if (!response.ok) {
      const error = new Error(`Kashier order lookup failed (${response.status})`);
      (error as { httpStatus?: number }).httpStatus = response.status;
      throw error;
    }
    const json = (await response.json()) as Record<string, unknown>;
    const orders = Array.isArray(json?.data) ? (json.data as Record<string, unknown>[]) : [];
    const order = orders.find((entry) => entry?.merchantOrderId === ref) ?? null;
    if (!order) return { found: false, payTransactions: [] };
    const transactions = Array.isArray(order.transactions) ? (order.transactions as Record<string, unknown>[]) : [];
    return {
      found: true,
      payTransactions: transactions
        .filter((txn) => txn?.operation === 'pay' && typeof txn?.transactionId === 'string')
        .map((txn) => ({
          transactionId: txn.transactionId as string,
          status: typeof txn.status === 'string' ? (txn.status as string) : null,
          amount: txn.amount,
          currency: txn.currency,
        })),
    };
  }
}
