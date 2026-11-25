import { validateEgyptianNationalId } from './national-id.util';

describe('Egyptian national ID validation', () => {
  it('accepts a valid 14-digit ID', () => {
    // Example: century 3 (2000s), make a reasonable date
    const id = '30201011234567';
    const result = validateEgyptianNationalId(id);
    expect(result.valid).toBe(true);
  });

  it('rejects wrong length', () => {
    expect(validateEgyptianNationalId('123').valid).toBe(false);
  });

  it('rejects wrong century', () => {
    const id = '10201011234567';
    const result = validateEgyptianNationalId(id);
    expect(result.valid).toBe(false);
    expect(result.error).toMatch(/century/);
  });

  it('rejects impossible date', () => {
    const id = '30202302345678'; // century 3, year 02, month 02, day 30 -> impossible (Feb 30)
    const result = validateEgyptianNationalId(id);
    expect(result.valid).toBe(false);
    expect(result.error).toMatch(/impossible/);
  });

  it('rejects age under 18', () => {
    const now = new Date('2026-10-17T00:00:00Z');
    const birthYear = now.getFullYear() - 16;
    const month = String((now.getMonth() + 1) % 12 || 1).padStart(2, '0');
    const day = '01';
    const yy = String(birthYear).slice(2).padStart(2, '0');
    const century = birthYear >= 2000 ? '3' : '2';
    const id = `${century}${yy}${month}${day}0134567`;
    const result = validateEgyptianNationalId(id, now);
    expect(result.valid).toBe(false);
    expect(result.error).toMatch(/at least 18/);
  });
});
