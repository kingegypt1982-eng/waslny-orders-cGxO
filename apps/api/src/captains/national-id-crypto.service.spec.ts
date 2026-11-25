import { InternalServerErrorException } from '@nestjs/common';
import { NationalIdCryptoService } from './national-id-crypto.service';

describe('NationalIdCryptoService', () => {
  const originalEnv = process.env.NATIONAL_ID_ENCRYPTION_KEY;
  const originalEnvHash = process.env.NATIONAL_ID_HASH_KEY;

  beforeEach(() => {
    process.env.NATIONAL_ID_ENCRYPTION_KEY = Buffer.from('a'.repeat(32)).toString('base64');
    delete process.env.NATIONAL_ID_HASH_KEY;
  });

  afterEach(() => {
    if (originalEnv === undefined) {
      delete process.env.NATIONAL_ID_ENCRYPTION_KEY;
    } else {
      process.env.NATIONAL_ID_ENCRYPTION_KEY = originalEnv;
    }
    if (originalEnvHash === undefined) {
      delete process.env.NATIONAL_ID_HASH_KEY;
    } else {
      process.env.NATIONAL_ID_HASH_KEY = originalEnvHash;
    }
  });

  it('encrypts and decrypts back to original', () => {
    const svc = new NationalIdCryptoService();
    const plaintext = '12345678901234';
    const encrypted = svc.encrypt(plaintext);
    expect(encrypted.split(':')).toHaveLength(4);
    expect(svc.decrypt(encrypted)).toBe(plaintext);
  });

  it('uses a different IV for each encryption', () => {
    const svc = new NationalIdCryptoService();
    const a = svc.encrypt('12345678901234');
    const b = svc.encrypt('12345678901234');
    expect(a).not.toBe(b);
    expect(svc.decrypt(a)).toBe('12345678901234');
    expect(svc.decrypt(b)).toBe('12345678901234');
  });

  it('hashes consistently and returns last4', () => {
    const svc = new NationalIdCryptoService();
    const h1 = svc.hash('12345678901234');
    const h2 = svc.hash('12345678901234');
    expect(h1).toBe(h2);
    expect(h1).toHaveLength(64); // sha256 hex
    expect(svc.last4('12345678901234')).toBe('1234');
  });

  it('throws if key is missing', () => {
    delete process.env.NATIONAL_ID_ENCRYPTION_KEY;
    expect(() => new NationalIdCryptoService()).toThrow(InternalServerErrorException);
  });

  it('throws if key is wrong length', () => {
    process.env.NATIONAL_ID_ENCRYPTION_KEY = 'dGVzdA=='; // 'test'
    expect(() => new NationalIdCryptoService()).toThrow(InternalServerErrorException);
  });
});
