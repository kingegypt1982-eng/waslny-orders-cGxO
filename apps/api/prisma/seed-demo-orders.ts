import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { ORDER_SEARCH_EXPIRY_MINUTES } from '../src/orders/orders.constants';

/**
 * Local-only demo data for the captain orders feed (Phase 3 screens).
 * Creates a demo client plus a handful of SEARCHING_CAPTAIN orders around
 * downtown Cairo, so the feed (radius + skip + accept) can be exercised
 * without a real client. Refuses to run in production.
 *
 * Usage: npm run seed:demo-orders
 */
const prisma = new PrismaClient();

const DEMO_CLIENT_EMAIL = 'demo.client@waslny.local';
const DEMO_CLIENT_PASSWORD = process.env.DEMO_CLIENT_PASSWORD ?? 'Demo@1234';
const DEMO_REFERENCE_PREFIX = 'DEMO-';

const radians = (degrees: number) => degrees * Math.PI / 180;
function distanceKm(fromLat: number, fromLon: number, toLat: number, toLon: number) {
  const deltaLat = radians(toLat - fromLat);
  const deltaLon = radians(toLon - fromLon);
  const arc = Math.sin(deltaLat / 2) ** 2 + Math.cos(radians(fromLat)) * Math.cos(radians(toLat)) * Math.sin(deltaLon / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(arc), Math.sqrt(1 - arc));
}

/** Near-downtown Cairo: all pickups sit within ~1.5 km of the centre. */
const CENTER = { lat: 30.0444, lng: 31.2357 };
const DEMO_ORDERS = [
  { reference: 'DEMO-0001', pickupLabel: 'وسط البلد - شارع طلعت حرب', deliveryLabel: 'الزمالك - شارع 26 يوليو', category: 'PACKAGE' as const, offset: 0.004 },
  { reference: 'DEMO-0002', pickupLabel: 'ميدان التحرير', deliveryLabel: 'جاردن سيتي', category: 'PAPERS' as const, offset: 0.006 },
  { reference: 'DEMO-0003', pickupLabel: 'شارع قصر النيل', deliveryLabel: 'الدقي', category: 'MATERIALS' as const, offset: 0.009 },
  { reference: 'DEMO-0004', pickupLabel: 'الأوبرا', deliveryLabel: 'المهندسين', category: 'SPARE_PARTS' as const, offset: 0.011 },
  { reference: 'DEMO-0005', pickupLabel: 'شارع شامبليون', deliveryLabel: 'العباسية', category: 'GOODS' as const, offset: 0.013 },
  { reference: 'DEMO-0006', pickupLabel: 'شارع رمسيس', deliveryLabel: 'شبرا', category: 'OTHER' as const, offset: 0.015 },
];

async function main() {
  if (process.env.NODE_ENV === 'production') {
    throw new Error('Refusing to seed demo orders in production.');
  }

  const passwordHash = await bcrypt.hash(DEMO_CLIENT_PASSWORD, 12);
  const client = await prisma.user.upsert({
    where: { email: DEMO_CLIENT_EMAIL },
    update: { role: 'CLIENT', suspendedAt: null, wallet: { upsert: { update: {}, create: { balance: 500, currency: 'EGP' } } } },
    create: {
      email: DEMO_CLIENT_EMAIL,
      name: 'Demo Client',
      phone: '+201000000000',
      passwordHash,
      role: 'CLIENT',
      wallet: { create: { balance: 500, currency: 'EGP' } },
    },
  });

  const pricing = await prisma.pricingSettings.upsert({ where: { id: 'default' }, update: {}, create: {} });
  const basePrice = Number(pricing.basePrice);
  const pricePerKm = Number(pricing.pricePerKm);
  const commissionPercent = Number(pricing.commissionPercent);

  const removed = await prisma.order.deleteMany({ where: { clientId: client.id } });

  let created = 0;
  for (const demo of DEMO_ORDERS) {
    const pickup = { latitude: CENTER.lat + demo.offset, longitude: CENTER.lng + demo.offset };
    const delivery = { latitude: CENTER.lat + demo.offset * 3, longitude: CENTER.lng + demo.offset * 3 };
    const distance = Math.round(distanceKm(pickup.latitude, pickup.longitude, delivery.latitude, delivery.longitude) * 100) / 100;
    const price = Number((basePrice + distance * pricePerKm).toFixed(2));
    const commission = Number((price * commissionPercent / 100).toFixed(2));
    await prisma.order.create({
      data: {
        reference: demo.reference,
        clientId: client.id,
        status: 'SEARCHING_CAPTAIN',
        pickupLabel: demo.pickupLabel,
        pickupLatitude: pickup.latitude,
        pickupLongitude: pickup.longitude,
        deliveryLabel: demo.deliveryLabel,
        deliveryLatitude: delivery.latitude,
        deliveryLongitude: delivery.longitude,
        category: demo.category,
        description: 'طلب تجريبي لاختبار شاشة الطلبات المتاحة',
        recipientName: 'مستلم تجريبي',
        recipientPhone: '+201000000000',
        distanceKm: distance,
        price,
        commission,
      },
    });
    created += 1;
  }

  console.log(`Demo orders ready: removed=${removed.count} created=${created} client=${DEMO_CLIENT_EMAIL}`);
  console.log(`Demo client password: ${DEMO_CLIENT_PASSWORD} (local development only)`);
  console.log(`Note: searches expire server-side after ${ORDER_SEARCH_EXPIRY_MINUTES} minutes - re-run this command right before a demo.`);
}

main()
  .catch((error) => {
    console.error('Demo order seed failed', error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
