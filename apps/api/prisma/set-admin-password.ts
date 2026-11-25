import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { findRejectedSecret } from '../src/security/secret-guard';

/**
 * Applies ADMIN_PASSWORD from the environment to the admin account's password
 * hash in the database. No reset token, no token expiry, no value printed.
 *
 *   npm run admin:set-password
 */
async function main(): Promise<void> {
  const password = process.env.ADMIN_PASSWORD;
  const email = process.env.ADMIN_EMAIL ?? 'admin@waslny.com';

  if (!password) {
    throw new Error('ADMIN_PASSWORD is not set. Export it (or use .env) before running this script.');
  }
  if (process.env.NODE_ENV !== 'development') {
    const problem = findRejectedSecret({ NODE_ENV: process.env.NODE_ENV, ADMIN_PASSWORD: password });
    if (problem) throw new Error(`${problem}. Refusing to apply it to the database.`);
  }

  const passwordHash = await bcrypt.hash(password, 12);
  const prisma = new PrismaClient();
  try {
    const updated = await prisma.user.updateMany({
      where: { email },
      data: { passwordHash },
    });
    if (updated.count === 0) {
      console.log('No account found for ADMIN_EMAIL. Run `npm run prisma:seed` first.');
      return;
    }
    console.log(`Admin password synced from ADMIN_PASSWORD (updated=${updated.count}).`);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error('admin:set-password failed:', error instanceof Error ? error.message : 'unknown error');
  process.exit(1);
});
