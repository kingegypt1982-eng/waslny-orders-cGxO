import { validate } from 'class-validator';
import { UpdatePricingDto } from './dto/update-pricing.dto';

function validDto(patch: Partial<UpdatePricingDto> = {}) {
  return Object.assign(new UpdatePricingDto(), {
    basePrice: 30,
    pricePerKm: 8,
    commissionPercent: 10,
    minimumWalletBalance: 0,
    ...patch,
  });
}

describe('UpdatePricingDto fee ranges', () => {
  it('accepts fee settings inside their ranges', async () => {
    expect(await validate(validDto({ paymentFeePercent: 2.5, paymentFeeFixed: 1 }))).toHaveLength(0);
    expect(await validate(validDto({ paymentFeePercent: 0, paymentFeeFixed: 0 }))).toHaveLength(0);
    expect(await validate(validDto({ paymentFeePercent: 20 }))).toHaveLength(0);
    expect(await validate(validDto({}))).toHaveLength(0);
  });

  it('rejects fee settings outside their ranges', async () => {
    expect((await validate(validDto({ paymentFeePercent: 25 }))).length).toBeGreaterThan(0);
    expect((await validate(validDto({ paymentFeePercent: -1 }))).length).toBeGreaterThan(0);
    expect((await validate(validDto({ paymentFeeFixed: -5 }))).length).toBeGreaterThan(0);
  });
});
