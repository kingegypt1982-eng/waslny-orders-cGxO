import { BadRequestException } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { mkdir, writeFile } from 'fs/promises';
import { dirname, join, resolve } from 'path';

/** Same storage style as captain documents: local `uploads/` dir, never statically served. */
export const PROOF_MAX_BYTES = 5 * 1024 * 1024;
export const PROOF_ROOT = 'proofs';

export interface ProofPhotoInput {
  buffer: Buffer;
  size: number;
}

const JPEG_SIG = [0xff, 0xd8, 0xff];
const PNG_SIG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const RIFF_SIG = [0x52, 0x49, 0x46, 0x46]; // 'RIFF'
const WEBP_SIG = [0x57, 0x45, 0x42, 0x50]; // 'WEBP' at offset 8

function startsWith(bytes: Buffer, signature: number[], offset = 0) {
  return signature.every((byte, index) => bytes[offset + index] === byte);
}

/** Detects the real image kind from magic bytes, never from the extension. */
export function detectProofImage(buffer: Buffer): { extension: string; mimeType: string } | null {
  if (buffer.length >= 3 && startsWith(buffer, JPEG_SIG)) return { extension: '.jpg', mimeType: 'image/jpeg' };
  if (buffer.length >= 8 && startsWith(buffer, PNG_SIG)) return { extension: '.png', mimeType: 'image/png' };
  if (buffer.length >= 12 && startsWith(buffer, RIFF_SIG) && startsWith(buffer, WEBP_SIG, 8)) {
    return { extension: '.webp', mimeType: 'image/webp' };
  }
  return null;
}

export function validateProofPhoto(file: ProofPhotoInput): { extension: string; mimeType: string } {
  if (!file?.buffer || file.size > PROOF_MAX_BYTES) {
    throw new BadRequestException('Photo must be at most 5 MB');
  }
  const kind = detectProofImage(file.buffer);
  if (!kind) throw new BadRequestException('Photo must be a real JPEG, PNG, or WebP image');
  return kind;
}

/** Windows `path.join` stores backslashes. Normalize so stored paths and prefix checks stay portable. */
export function toPosixPath(relativePath: string): string {
  return relativePath.split('\\').join('/');
}

export async function saveProofPhoto(orderId: string, file: ProofPhotoInput) {
  const { extension, mimeType } = validateProofPhoto(file);
  const relativePath = toPosixPath(join(PROOF_ROOT, orderId, `${randomUUID()}${extension}`));
  const absolutePath = join(process.cwd(), 'uploads', relativePath);
  await mkdir(dirname(absolutePath), { recursive: true });
  await writeFile(absolutePath, file.buffer);
  return { relativePath, mimeType };
}

/** Same traversal-guard style as admin captain documents. Returns null when unsafe. */
export function resolveUploadPath(relativePath: string) {
  const root = resolve(process.cwd(), 'uploads');
  const path = resolve(root, toPosixPath(relativePath));
  if (!path.startsWith(`${root}/`) && !path.startsWith(`${root}\\`)) return null;
  return { root, path };
}
