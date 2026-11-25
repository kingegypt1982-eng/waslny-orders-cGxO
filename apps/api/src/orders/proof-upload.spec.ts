import { BadRequestException } from '@nestjs/common';
import { detectProofImage, toPosixPath, validateProofPhoto } from './proof-upload';

describe('proof-upload validation', () => {
  const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00]);
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46]);
  const webp = Buffer.from([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50, 0x00]);
  const pdf = Buffer.from('%PDF-1.4 fake');

  it('accepts real JPEG, PNG, and WebP images by magic bytes', () => {
    expect(detectProofImage(jpeg)).toMatchObject({ extension: '.jpg', mimeType: 'image/jpeg' });
    expect(detectProofImage(png)).toMatchObject({ extension: '.png', mimeType: 'image/png' });
    expect(detectProofImage(webp)).toMatchObject({ extension: '.webp', mimeType: 'image/webp' });
  });

  it('rejects non-image content even with an image mimetype', () => {
    expect(detectProofImage(pdf)).toBeNull();
    expect(() => validateProofPhoto({ buffer: pdf, size: pdf.length })).toThrow(BadRequestException);
  });

  it('rejects oversized and empty photos', () => {
    expect(() => validateProofPhoto({ buffer: png, size: 5 * 1024 * 1024 + 1 })).toThrow(BadRequestException);
    expect(() => validateProofPhoto({ buffer: Buffer.alloc(0), size: 0 })).toThrow(BadRequestException);
  });

  it('stores and compares upload paths with forward slashes on every platform', () => {
    expect(toPosixPath('captains\\u1\\a.jpg')).toBe('captains/u1/a.jpg');
    expect(toPosixPath('proofs/o1/a.webp')).toBe('proofs/o1/a.webp');
    expect(toPosixPath('captains\\u1/../u2/a.jpg')).toBe('captains/u1/../u2/a.jpg');
  });
});
