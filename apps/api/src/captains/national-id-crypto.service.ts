import { createCipheriv, createDecipheriv, createHmac, randomBytes } from 'crypto';
import { Injectable, InternalServerErrorException } from '@nestjs/common';

const ALGORITHM = 'aes-256-gcm';
const IV_LENGTH = 12; // 96-bit nonce
const AUTH_TAG_LENGTH = 16;
const KEY_LENGTH = 32;

@Injectable()
export class NationalIdCryptoService {
  private readonly encryptionKey: Buffer;
  private readonly hashKey: Buffer;

  constructor() {
    this.encryptionKey = this.loadKey('NATIONAL_ID_ENCRYPTION_KEY');
    this.hashKey = process.env.NATIONAL_ID_HASH_KEY
      ? this.loadKey('NATIONAL_ID_HASH_KEY')
      : this.encryptionKey;
  }

  private loadKey(name: string): Buffer {
    const raw = process.env[name];
    if (!raw || !raw.trim()) {
      throw new InternalServerErrorException(`${name} is not set. Refusing to handle national ID data without an encryption key.`);
    }
    const key = Buffer.from(raw.trim(), 'base64');
    if (key.length !== KEY_LENGTH) {
      throw new InternalServerErrorException(`${name} must be a base64-encoded 32-byte (256-bit) key.`);
    }
    return key;
  }

  encrypt(plaintext: string): string {
    const iv = randomBytes(IV_LENGTH);
    const cipher = createCipheriv(ALGORITHM, this.encryptionKey, iv, { authTagLength: AUTH_TAG_LENGTH });
    const encrypted = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();
    return ['v1', iv.toString('base64'), encrypted.toString('base64'), tag.toString('base64')].join(':');
  }

  decrypt(payload: string): string {
    const parts = (payload ?? '').split(':');
    if (parts.length !== 4 || parts[0] !== 'v1' || !parts[1] || !parts[2] || !parts[3]) {
      throw new InternalServerErrorException('Stored national ID is not in a recognized format.');
    }
    const [version, ivB64, dataB64, tagB64] = parts;
    if (version !== 'v1') {
      throw new InternalServerErrorException('Stored national ID is not in a recognized format.');
    }
    const decipher = createDecipheriv(ALGORITHM, this.encryptionKey, Buffer.from(ivB64, 'base64'), { authTagLength: AUTH_TAG_LENGTH });
    decipher.setAuthTag(Buffer.from(tagB64, 'base64'));
    return Buffer.concat([decipher.update(Buffer.from(dataB64, 'base64')), decipher.final()]).toString('utf8');
  }

  hash(nationalId: string): string {
    const normalized = (nationalId ?? '').trim();
    return createHmac('sha256', this.hashKey).update(normalized).digest('hex');
  }

  last4(nationalId: string): string {
    const normalized = (nationalId ?? '').trim();
    return normalized.slice(-4) || '';
  }
}
