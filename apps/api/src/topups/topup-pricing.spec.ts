import { Prisma } from '@prisma/client';
import { computeTopUpCharge } from './topup-pricing';

describe('computeTopUpCharge (Decimal only, no floats)', () => {
  it('grosses 100 up at 2.5% + 0 fixed to charge 102.57 / fee 2.57 (ceiling)', () => {
    // 100 / 0.975 = 102.564102... -> ceil to 102.57 (never under-covers the fee)
    const q = computeTopUpCharge(100, 2.5, 0);
    expect(q.credit.toFixed(2)).toBe('100.00');
    expect(q.charge.toFixed(2)).toBe('102.57');
    expect(q.fee.toFixed(2)).toBe('2.57');
    expect(q.charge.minus(q.credit).equals(q.fee)).toBe(true);
  });

  it('adds the fixed fee before gross-up: 100 at 2.5% + 1 fixed', () => {
    // (100 + 1) / (1 - 0.025) = 101 / 0.975 = 103.589743... -> ceil 103.59
    const q = computeTopUpCharge(100, 2.5, 1);
    expect(q.charge.toFixed(2)).toBe('103.59');
    expect(q.fee.toFixed(2)).toBe('3.59');
    expect(q.credit.toFixed(2)).toBe('100.00');
  });

  it('returns charge == credit when percent and fixed are zero', () => {
    const q = computeTopUpCharge(250, 0, 0);
    expect(q.charge.equals(q.credit)).toBe(true);
    expect(q.fee.isZero()).toBe(true);
  });

  it('never adds an extra piaster to already-exact amounts', () => {
    // 999999 / 0.8 = 1249998.75 exact at 20% -> untouched
    const big = computeTopUpCharge(999999, 20, 0);
    expect(big.charge.toFixed(2)).toBe('1249998.75');
    expect(big.fee.toFixed(2)).toBe('249999.75');
    // percent=0 leaves any amount byte-identical
    const exact = computeTopUpCharge(125.5, 0, 0);
    expect(exact.charge.toFixed(2)).toBe('125.50');
    expect(exact.fee.isZero()).toBe(true);
  });

  it('rounds fractional remainders up (ceiling)', () => {
    // 0.01 / 0.975 = 0.010256... -> 0.02, fee 0.01
    const tiny = computeTopUpCharge(0.01, 2.5, 0);
    expect(tiny.charge.toFixed(2)).toBe('0.02');
    expect(tiny.fee.toFixed(2)).toBe('0.01');
  });

  it('returns Decimal instances, never floats', () => {
    const q = computeTopUpCharge(100, 2.5, 0);
    expect(q.credit).toBeInstanceOf(Prisma.Decimal);
    expect(q.charge).toBeInstanceOf(Prisma.Decimal);
    expect(q.fee).toBeInstanceOf(Prisma.Decimal);
  });

  it('rejects out-of-range fee configuration', () => {
    expect(() => computeTopUpCharge(100, 100, 0)).toThrow();
    expect(() => computeTopUpCharge(100, -1, 0)).toThrow();
    expect(() => computeTopUpCharge(100, 2.5, -1)).toThrow();
  });
});
