import { Prisma } from '@prisma/client';

export interface TopUpQuote {
  credit: Prisma.Decimal;
  charge: Prisma.Decimal;
  fee: Prisma.Decimal;
}

/**
 * Kashier fee gross-up — the single central computation for top-up pricing.
 * All money math stays in Decimal; floats are never used.
 *
 *   charge = ceil_to_2dp((credit + fixed) / (1 - percent/100))
 *   fee    = charge - credit
 *
 * Rounding decision: a TRUE ceiling (Decimal ROUND_UP; all inputs here are
 * non-negative, so ROUND_UP == ceil) guarantees the charged amount always
 * covers the fee — e.g. 100 @ 2.5% gives 102.5641… -> 102.57, never 102.56,
 * so no fractional piaster of the fee is ever lost. Exact 2dp values are
 * untouched (ceiling only rounds up a non-zero remainder).
 */
export function computeTopUpCharge(
  creditAmount: number | string | Prisma.Decimal,
  percent: number | string | Prisma.Decimal,
  fixed: number | string | Prisma.Decimal,
): TopUpQuote {
  const credit = new Prisma.Decimal(creditAmount);
  const pct = new Prisma.Decimal(percent);
  const fix = new Prisma.Decimal(fixed);
  if (pct.isNegative() || pct.greaterThanOrEqualTo(100)) {
    throw new Error('paymentFeePercent out of range [0, 100)');
  }
  if (fix.isNegative()) {
    throw new Error('paymentFeeFixed must be >= 0');
  }
  const divisor = new Prisma.Decimal(1).minus(pct.div(100));
  const charge = credit.plus(fix).div(divisor).toDecimalPlaces(2, Prisma.Decimal.ROUND_UP);
  const fee = charge.minus(credit);
  return { credit, charge, fee };
}
