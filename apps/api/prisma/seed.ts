import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { findRejectedSecret } from '../src/security/secret-guard';

const prisma = new PrismaClient();

async function main() {
  const isProduction = process.env.NODE_ENV === 'production';
  // The email may fall back to the development default; the password never
  // does, in any environment.
  const adminEmail = process.env.ADMIN_EMAIL ?? (isProduction ? undefined : 'admin@waslny.com');
  const adminPassword = process.env.ADMIN_PASSWORD;
  if (!adminEmail) {
    throw new Error('ADMIN_EMAIL is not set. Set it before running `npm run prisma:seed`.');
  }
  if (!adminPassword || !adminPassword.trim()) {
    throw new Error(
      'ADMIN_PASSWORD is not set. Set it in apps/api/.env (or export it) before running `npm run prisma:seed`. There is no default password.',
    );
  }
  // Known placeholders (including the former development default) are refused
  // in every environment so a documented password can never become a live login.
  const problem = findRejectedSecret({ NODE_ENV: process.env.NODE_ENV, ADMIN_PASSWORD: adminPassword });
  if (problem) throw new Error(`${problem}. Set a unique ADMIN_PASSWORD before seeding.`);

  const passwordHash = await bcrypt.hash(adminPassword, 12);

  await prisma.user.upsert({
    where: { email: adminEmail },
    update: {
      name: 'System Admin',
      passwordHash,
      role: 'ADMIN',
      suspendedAt: null,
      wallet: { upsert: { update: {}, create: { balance: 0, currency: 'EGP' } } },
    },
    create: {
      email: adminEmail,
      name: 'System Admin',
      passwordHash,
      role: 'ADMIN',
      wallet: {
        create: {
          balance: 0,
          currency: 'EGP',
        },
      },
    },
  });

  await prisma.pricingSettings.upsert({
    where: { id: 'default' },
    update: {
      basePrice: 30,
      pricePerKm: 8,
      commissionPercent: 10,
      minimumWalletBalance: 0,
      currency: 'EGP',
      minRadiusKm: 0.5,
      maxRadiusKm: 15,
    },
    create: {
      id: 'default',
      basePrice: 30,
      pricePerKm: 8,
      commissionPercent: 10,
      minimumWalletBalance: 0,
      currency: 'EGP',
      minRadiusKm: 0.5,
      maxRadiusKm: 15,
    },
  });

  console.log(`Seed complete: admin account ${adminEmail} + default pricing`);
}

main()
  .catch((error) => {
    console.error('Seed failed', error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
