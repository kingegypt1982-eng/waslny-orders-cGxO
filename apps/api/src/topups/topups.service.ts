import {
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  ConflictException,
  ServiceUnavailableException,
  UnauthorizedException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { CaptainStatus, Prisma, TopUpStatus, WalletTransactionType } from '@prisma/client';
import { randomUUID } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { KashierClient } from './kashier.client';
import { resolvePaymentReturnUrl } from './payment-return-url';
import { computeTopUpCharge } from './topup-pricing';
import { AdminTopUpsQueryDto } from './dto/admin-topups-query.dto';

/** Sessions older than this with no final event are swept to EXPIRED. */
const TOPUP_EXPIRY_MINUTES = 60;

/**
 * A still-PENDING top-up for the same captain and net amount created within
 * this window is reused instead of creating a second row (and a second
 * Kashier session). This is the server-side guard against rapid double taps
 * and client retries; the Kashier order reference stays globally unique.
 */
const TOPUP_REUSE_WINDOW_MINUTES = 3;

/**
 * Kashier money unit: MAJOR units as decimals (e.g. webhook `amount: 50`
 * means 50.00 EGP), proven by a live reconciliation lookup of a real
 * sandbox payment (order amount 50 / pay-transaction amount 50, both EGP).
 * Evidence: docs/KASHIER_DIAGNOSIS.md ("الدليل 2"). See also the amounts in
 * https://developers.kashier.io/docs/accept-payments/order-reconciliation
 * (e.g. `"amount": 11179.51`) vs session creation (`"amount": "100.00"` in
 * https://developers.kashier.io/docs/accept-payments/payment-sessions).
 * Both sides are normalized to exactly 2 decimals and compared with zero
 * tolerance — never floats, never minor/major guessing.
 */
function normalizeAmount(value: unknown): string | null {
  try {
    if (value === null || value === undefined || value === '') return null;
    return new Prisma.Decimal(String(value)).toFixed(2);
  } catch {
    return null;
  }
}

/** Only this failure reason is eligible for governed reprocessing (see below). */
const MISMATCH_REASON = 'Amount or currency mismatch';
/** A failed confirmation inquiry with this reason may be retried by reconciliation (see below). */
const UNCONFIRMED_REASON = 'Transaction not confirmed successful';

/**
 * Stored-status vocabulary for Kashier transactions.
 * - SUCCESS: terminal success.
 * - FAILURE: terminal failure.
 * - PENDING / UNKNOWN / anything else: intermediate — leave the TopUp alone.
 * Docs: https://developers.kashier.io/docs/accept-payments/transactions#transaction-statuses
 * (details endpoint + webhooks report the stored status; the list projection
 * vocabulary Approved/Rejected/Unknown/Expired/Pending is display-only and is
 * never used for money decisions here.)
 */
export function classifyStoredStatus(status: string | null): 'success' | 'failure' | 'intermediate' {
  const normalized = (status ?? '').toUpperCase();
  if (normalized === 'SUCCESS') return 'success';
  if (normalized === 'FAILURE') return 'failure';
  return 'intermediate';
}

@Injectable()
export class TopUpsService {
  private readonly logger = new Logger(TopUpsService.name);

  constructor(private readonly prisma: PrismaService, private readonly kashier: KashierClient) {}

  private async expireStale() {
    const cutoff = new Date(Date.now() - TOPUP_EXPIRY_MINUTES * 60_000);
    await this.prisma.topUp.updateMany({
      where: { status: TopUpStatus.PENDING, createdAt: { lt: cutoff } },
      data: { status: TopUpStatus.EXPIRED, failureReason: 'Session expired' },
    });
  }

  async createTopUp(userId: string, amount: number, returnOrigin?: string) {
    const profile = await this.prisma.captainProfile.findUnique({ where: { userId } });
    if (!profile || profile.status !== CaptainStatus.ACTIVE) {
      throw new ForbiddenException('Only approved captains can top up');
    }
    const pricing = await this.prisma.pricingSettings.upsert({ where: { id: 'default' }, update: {}, create: {} });
    const min = Number(pricing.minTopUpAmount);
    const max = Number(pricing.maxTopUpAmount);
    // Limits apply to the credited amount (net wallet addition), as before.
    if (!Number.isFinite(amount) || amount < min || amount > max) {
      throw new UnprocessableEntityException(`Amount must be between ${min} and ${max} EGP`);
    }
    await this.expireStale();
    // Gross-up snapshot: later admin edits to the fee settings never rewrite
    // the history of an existing TopUp — the webhook compares and credits
    // strictly from these stored values.
    const quote = computeTopUpCharge(amount, pricing.paymentFeePercent, pricing.paymentFeeFixed);
    // Server-side idempotency: if this captain already has a recent PENDING
    // top-up for the same net amount with a live checkout URL, hand it back
    // instead of creating a duplicate row and a duplicate Kashier session.
    const reusable = await this.prisma.topUp.findFirst({
      where: {
        userId,
        status: TopUpStatus.PENDING,
        creditAmount: quote.credit,
        checkoutUrl: { not: null },
        createdAt: { gt: new Date(Date.now() - TOPUP_REUSE_WINDOW_MINUTES * 60_000) },
      },
      orderBy: { createdAt: 'desc' },
    });
    if (reusable) {
      return {
        topUpId: reusable.id,
        checkoutUrl: reusable.checkoutUrl as string,
        creditAmount: reusable.creditAmount.toNumber(),
        chargeAmount: reusable.chargeAmount.toNumber(),
        feeAmount: reusable.feeAmount.toNumber(),
      };
    }
    const redirectUrl = resolvePaymentReturnUrl({
      origin: returnOrigin,
      clientOrigin: process.env.CLIENT_ORIGIN,
      configuredRedirectUrl: this.kashier.redirectUrl,
    });
    if (!redirectUrl) {
      throw new ServiceUnavailableException('A valid HTTP(S) payment return URL is not configured');
    }
    // Unstructured, unguessable merchant reference (Kashier rejects duplicates).
    const providerOrderRef = `topup_${randomUUID().replace(/-/g, '')}`;
    const topUp = await this.prisma.topUp.create({
      data: {
        userId,
        amount,
        creditAmount: quote.credit,
        chargeAmount: quote.charge,
        feeAmount: quote.fee,
        feePercent: pricing.paymentFeePercent,
        feeFixed: pricing.paymentFeeFixed,
        currency: 'EGP',
        providerOrderRef,
      },
    });
    try {
      // Kashier requires a customer object on session creation.
      const account = await this.prisma.user.findUnique({ where: { id: userId }, select: { email: true } });
      // Return the payer to the app origin that started the checkout (or the
      // configured app origin), never to an ephemeral tunnel host.
      const session = await this.kashier.createSession({
        amount: quote.charge.toFixed(2),
        currency: 'EGP',
        orderRef: providerOrderRef,
        description: `Wallet top-up ${providerOrderRef}`,
        redirectUrl,
        customer: { email: account?.email, reference: userId },
      });
      await this.prisma.topUp.update({
        where: { id: topUp.id },
        data: { providerSessionId: session.sessionId, checkoutUrl: session.checkoutUrl },
      });
      return {
        topUpId: topUp.id,
        checkoutUrl: session.checkoutUrl,
        creditAmount: quote.credit.toNumber(),
        chargeAmount: quote.charge.toNumber(),
        feeAmount: quote.fee.toNumber(),
      };
    } catch {
      await this.prisma.topUp.update({
        where: { id: topUp.id },
        data: { status: TopUpStatus.FAILED, failureReason: 'Payment provider is temporarily unavailable' },
      });
      throw new ServiceUnavailableException('Payment provider is temporarily unavailable. Please try again.');
    }
  }

  listTopUps(userId: string, take = 50, skip = 0) {
    return this.prisma.topUp.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: Math.min(take, 100),
      skip: Math.max(skip, 0),
    });
  }

  async getTopUp(userId: string, id: string) {
    const topUp = await this.prisma.topUp.findUnique({ where: { id } });
    if (!topUp || topUp.userId !== userId) throw new ForbiddenException();
    return topUp;
  }

  async simulateDevelopmentSuccess(userId: string, id: string) {
    if (process.env.NODE_ENV !== 'development') {
      throw new ForbiddenException('Development top-up simulation is disabled');
    }
    const topUp = await this.prisma.topUp.findUnique({ where: { id } });
    if (!topUp || topUp.userId !== userId) throw new ForbiddenException();
    if (topUp.status === TopUpStatus.SUCCEEDED) {
      return { status: topUp.status, credited: false };
    }
    if (topUp.status !== TopUpStatus.PENDING) {
      throw new ConflictException('Only pending top-ups can be simulated');
    }

    const outcome = await this.prisma.$transaction((tx: Prisma.TransactionClient) =>
      this.claimAndCredit(tx, topUp, `development_${topUp.id}`),
    );
    if (outcome === 'duplicate') {
      const current = await this.prisma.topUp.findUnique({ where: { id } });
      return { status: current?.status ?? topUp.status, credited: false };
    }
    return { status: TopUpStatus.SUCCEEDED, credited: true };
  }

  adminTopUps(query: AdminTopUpsQueryDto) {
    const where: Prisma.TopUpWhereInput = {};
    if (query.status) where.status = query.status as TopUpStatus;
    if (query.userId) where.userId = query.userId;
    return this.prisma.topUp.findMany({
      where,
      take: query.take ?? 100,
      skip: query.skip ?? 0,
      orderBy: { createdAt: 'desc' },
      include: { user: { select: { id: true, name: true, email: true } } },
    });
  }

  /**
   * Kashier webhook handler. Always returns 200 ({ acknowledged: true }) after
   * a valid signature — including unknown refs and replays — and 401 before
   * any processing when the signature is invalid.
   * Every branch logs ref + outcome (+ status when known). Logs never carry
   * keys, signatures, or card data.
   * Docs: https://developers.kashier.io/docs/webhooks#step-3-respond-to-events
   */
  async handleWebhook(headerSignature: string | undefined, body: any): Promise<{ acknowledged: boolean }> {
    const data = body?.data as Record<string, unknown> | undefined;
    if (!data || typeof data !== 'object' || !this.kashier.verifyWebhook(data, headerSignature)) {
      this.logger.warn('kashier webhook invalid-signature');
      // Generic HTTP 401: no explanation of which check failed reaches the caller.
      throw new UnauthorizedException();
    }
    const ref = typeof data.merchantOrderId === 'string' ? data.merchantOrderId : null;
    if (!ref) {
      this.logger.warn('kashier webhook unknown (missing merchantOrderId)');
      return { acknowledged: true };
    }
    const topUp = await this.prisma.topUp.findUnique({ where: { providerOrderRef: ref } });
    if (!topUp) {
      this.logger.warn(`kashier webhook unknown ref=${ref}`);
      return { acknowledged: true };
    }
    const log = (outcome: string, extra = '') =>
      this.logger.log(`kashier webhook ${outcome} ref=${ref} status=${topUp.status}${extra}`);
    // Idempotency + governed reprocessing: PENDING and late EXPIRED proceed;
    // SUCCEEDED and terminal FAILED stay untouched — EXCEPT a FAILED whose
    // recorded reason is exactly the (now fixed) units mismatch or an
    // unconfirmed inquiry (see reconcilePendingBatch). A FAILED for any other
    // reason (real payment failure) is final and never reprocessed:
    // only a fresh successful payment event for the same reference could move
    // money, and re-crediting a genuinely failed payment would be wrong.
    const reprocessable =
      topUp.status === TopUpStatus.PENDING ||
      topUp.status === TopUpStatus.EXPIRED ||
      (topUp.status === TopUpStatus.FAILED &&
        (topUp.failureReason === MISMATCH_REASON || topUp.failureReason === UNCONFIRMED_REASON));
    if (!reprocessable) {
      log('duplicate');
      return { acknowledged: true };
    }
    const expectedAmount = normalizeAmount(topUp.chargeAmount);
    const gotAmount = normalizeAmount(data.amount);
    if (!expectedAmount || !gotAmount || gotAmount !== expectedAmount || data.currency !== topUp.currency) {
      await this.prisma.topUp.update({
        where: { id: topUp.id },
        data: { status: TopUpStatus.FAILED, failureReason: MISMATCH_REASON },
      });
      log(`mismatch expected=${expectedAmount ?? '?'} got=${String(data.amount)}`);
      return { acknowledged: true };
    }
    const webhookStatus = String((data as Record<string, unknown>).status ?? '').toUpperCase();
    if (webhookStatus !== 'SUCCESS') {
      // PENDING webhooks are intermediate: leave the TopUp alone, the final
      // event will follow. Anything else is terminal failure.
      // Docs: https://developers.kashier.io/docs/webhooks#events
      if (webhookStatus === 'PENDING') {
        log('not-pending');
        return { acknowledged: true };
      }
      await this.prisma.topUp.update({
        where: { id: topUp.id },
        data: { status: TopUpStatus.FAILED, failureReason: `Kashier reported ${webhookStatus || 'unknown'}` },
      });
      log('failed-payment');
      return { acknowledged: true };
    }
    // Never trust the push alone: confirm the stored transaction status with
    // Kashier before moving money. Unreachable verifier = fail closed: the
    // TopUp is left untouched and we still answer 200. Note this does NOT
    // guarantee Kashier retries (a 200 counts as delivered) — the row simply
    // waits for the next event or the periodic reconciler.
    // Docs: https://developers.kashier.io/docs/accept-payments/transactions#get-transaction-details
    const transactionId = (data as Record<string, unknown>).transactionId;
    if (typeof transactionId !== 'string' || !transactionId) {
      await this.prisma.topUp.update({
        where: { id: topUp.id },
        data: { status: TopUpStatus.FAILED, failureReason: 'Missing transaction reference' },
      });
      log('failed-payment');
      return { acknowledged: true };
    }
    let confirmed: { status: string | null };
    try {
      confirmed = await this.kashier.getTransactionStatus(transactionId);
    } catch (error) {
      const http = (error as { httpStatus?: number })?.httpStatus;
      log('not-pending', ` inquiry-unreachable${http ? ` http=${http}` : ''}`);
      return { acknowledged: true };
    }
    // Intermediate inquiry results (PENDING / UNKNOWN / unrecognized) leave
    // the TopUp untouched to await the final event; only a documented
    // terminal FAILURE is recorded. See classifyStoredStatus.
    const verdict = classifyStoredStatus(confirmed.status);
    if (verdict === 'intermediate') {
      log('pending-inquiry', ` reported=${confirmed.status ?? 'none'}`);
      return { acknowledged: true };
    }
    if (verdict !== 'success') {
      await this.prisma.topUp.update({
        where: { id: topUp.id },
        data: { status: TopUpStatus.FAILED, failureReason: UNCONFIRMED_REASON },
      });
      log('failed-payment', ` inquiry=${confirmed.status}`);
      return { acknowledged: true };
    }
    // A credit from PENDING is a first charge; from EXPIRED or an eligible
    // FAILED it is a governed reprocessing of money that verifiably arrived.
    const outcome = topUp.status === TopUpStatus.PENDING ? 'charged' : 'reprocessed';
    try {
      const result = await this.prisma.$transaction((tx: Prisma.TransactionClient) => this.claimAndCredit(tx, topUp, transactionId));
      log(result);
    } catch (error) {
      // providerTransactionId is unique: a replay across references cannot
      // credit twice — treat as already processed.
      if ((error as { code?: string })?.code === 'P2002') {
        log('duplicate');
        return { acknowledged: true };
      }
      throw error;
    }
    return { acknowledged: true };
  }

  /**
   * The single atomic credit path, shared verbatim by the webhook handler and
   * the periodic reconciler: conditional claim (exactly one concurrent winner)
   * + wallet increment of the NET credit + one unique TOP_UP ledger row.
   * Returns the outcome for logging ('charged' | 'reprocessed' | 'duplicate').
   */
  private async claimAndCredit(
    tx: Prisma.TransactionClient,
    topUp: {
      id: string;
      userId: string;
      status: TopUpStatus;
      creditAmount: Prisma.Decimal;
      currency: string;
      providerOrderRef: string;
    },
    transactionId: string,
  ): Promise<'charged' | 'reprocessed' | 'duplicate'> {
    // A FAILED row can only be claimed with its exact eligible reason, so a
    // FAILED for any other cause stays final even under replay or reconcile.
    const claimed = await tx.topUp.updateMany({
      where: {
        id: topUp.id,
        OR: [
          { status: { in: [TopUpStatus.PENDING, TopUpStatus.EXPIRED] } },
          { status: TopUpStatus.FAILED, failureReason: MISMATCH_REASON },
          { status: TopUpStatus.FAILED, failureReason: UNCONFIRMED_REASON },
        ],
      },
      data: { status: TopUpStatus.SUCCEEDED, paidAt: new Date(), providerTransactionId: transactionId },
    });
    if (!claimed.count) return 'duplicate';
    // Only the net credit reaches the wallet — the fee stays with Kashier.
    await tx.wallet.update({ where: { userId: topUp.userId }, data: { balance: { increment: topUp.creditAmount } } });
    await tx.walletTransaction.create({
      data: {
        userId: topUp.userId,
        topUpId: topUp.id,
        type: WalletTransactionType.TOP_UP,
        amount: topUp.creditAmount,
        currency: topUp.currency,
        note: `Wallet top-up ${topUp.providerOrderRef} confirmed (net ${topUp.creditAmount} after fees)`,
      },
    });
    return topUp.status === TopUpStatus.PENDING ? 'charged' : 'reprocessed';
  }

  /**
   * Periodic reconciliation (driven every 60s by TopupsScheduler, never
   * overlapping): re-checks PENDING top-ups older than 30s but younger than
   * the 60-minute expiry, plus UNCONFIRMED-failed rows younger than 7 days,
   * against Kashier's order lookup. At most 20 rows per cycle.
   * A row is credited only through claimAndCredit — the same conditional,
   * single-winner, unique-ledger path the webhook uses — so a webhook racing
   * this job cannot double-credit.
   */
  async reconcilePendingBatch(now: Date = new Date()): Promise<{ checked: number; charged: number }> {
    const sixtyMinutesAgo = new Date(now.getTime() - 60 * 60_000);
    const thirtySecondsAgo = new Date(now.getTime() - 30_000);
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60_000);
    const candidates = await this.prisma.topUp.findMany({
      where: {
        OR: [
          { status: TopUpStatus.PENDING, createdAt: { gt: sixtyMinutesAgo, lt: thirtySecondsAgo } },
          { status: TopUpStatus.FAILED, failureReason: UNCONFIRMED_REASON, createdAt: { gt: sevenDaysAgo } },
        ],
      },
      orderBy: { createdAt: 'asc' },
      take: 20,
    });
    let charged = 0;
    for (const topUp of candidates) {
      try {
        const lookup = await this.kashier.getOrderByMerchantRef(topUp.providerOrderRef);
        if (!lookup.found) continue;
        const success = lookup.payTransactions.find((txn) => classifyStoredStatus(txn.status) === 'success');
        if (success) {
          const expected = normalizeAmount(topUp.chargeAmount);
          const got = normalizeAmount(success.amount);
          if (!expected || !got || got !== expected || success.currency !== topUp.currency) {
            await this.prisma.topUp.update({
              where: { id: topUp.id },
              data: { status: TopUpStatus.FAILED, failureReason: MISMATCH_REASON },
            });
            this.logger.warn(`kashier reconcile mismatch ref=${topUp.providerOrderRef} status=${topUp.status}`);
            continue;
          }
          const outcome = await this.prisma.$transaction((tx: Prisma.TransactionClient) => this.claimAndCredit(tx, topUp, success.transactionId));
          if (outcome !== 'duplicate') {
            charged += 1;
            this.logger.log(`kashier reconcile ${outcome} ref=${topUp.providerOrderRef} status=${topUp.status}`);
          } else {
            this.logger.log(`kashier reconcile duplicate ref=${topUp.providerOrderRef} status=${topUp.status}`);
          }
          continue;
        }
        const failed = lookup.payTransactions.find((txn) => classifyStoredStatus(txn.status) === 'failure');
        if (failed) {
          await this.prisma.topUp.update({
            where: { id: topUp.id },
            data: { status: TopUpStatus.FAILED, failureReason: `Kashier reported ${failed.status}` },
          });
          this.logger.warn(`kashier reconcile failed-payment ref=${topUp.providerOrderRef} status=${topUp.status}`);
        }
        // Intermediate or no pay transaction yet: leave the row for the next cycle.
      } catch {
        // Transient lookup failure (network/HTTP): leave the row untouched.
        continue;
      }
    }
    return { checked: candidates.length, charged };
  }
}
