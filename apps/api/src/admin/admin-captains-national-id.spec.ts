import { AdminService } from './admin.service';
import { NationalIdCryptoService } from '../captains/national-id-crypto.service';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { OrderEventsService } from '../order-events/order-events.service';
import { ChatService } from '../firebase/chat.service';

describe('AdminService captains national ID', () => {
  const originalKey = process.env.NATIONAL_ID_ENCRYPTION_KEY;
  let crypto: NationalIdCryptoService;

  beforeAll(() => {
    process.env.NATIONAL_ID_ENCRYPTION_KEY = Buffer.from('z'.repeat(32)).toString('base64');
    crypto = new NationalIdCryptoService();
  });

  afterAll(() => {
    if (originalKey === undefined) delete process.env.NATIONAL_ID_ENCRYPTION_KEY;
    else process.env.NATIONAL_ID_ENCRYPTION_KEY = originalKey;
  });

  it('never returns the full national ID to admins, only the last 4 digits', async () => {
    const prisma = {
      captainProfile: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'p1',
            userId: 'u1',
            nationalIdEncrypted: crypto.encrypt('30201011234567'),
            nationalIdHash: crypto.hash('30201011234567'),
            nationalIdLast4: '4567',
            user: { id: 'u1', name: 'Cap', phone: '01000000000' },
          },
        ]),
      },
    };
    const chat = { getOrderChat: jest.fn() };
    const service = new AdminService(
      prisma as unknown as PrismaService,
      { create: jest.fn() } as unknown as NotificationsService,
      new OrderEventsService(prisma as unknown as PrismaService),
      chat as any,
      crypto,
    );

    const result = await service.captains({});
    expect(result[0].nationalIdDecrypted).toBeUndefined();
    expect(result[0].nationalIdLast4).toBe('4567');
    expect(result[0].nationalIdEncrypted).toBeUndefined();
    expect(result[0].nationalIdHash).toBeUndefined();
    expect(JSON.stringify(result)).not.toContain('30201011234567');
  });

  it('masks the national ID on the single-captain review endpoint too', async () => {
    const profile = {
      id: 'p1',
      userId: 'u1',
      nationalIdEncrypted: crypto.encrypt('30201011234567'),
      nationalIdHash: crypto.hash('30201011234567'),
      nationalIdLast4: '4567',
      user: { id: 'u1', name: 'Cap' },
    };
    const prisma = {
      captainProfile: { findUnique: jest.fn().mockResolvedValue(profile) },
    };
    const chat = { getOrderChat: jest.fn() };
    const service = new AdminService(
      prisma as unknown as PrismaService,
      { create: jest.fn() } as unknown as NotificationsService,
      new OrderEventsService(prisma as unknown as PrismaService),
      chat as any,
      crypto,
    );

    const result = await service.captain('u1');
    expect(result.nationalIdDecrypted).toBeUndefined();
    expect(result.nationalIdLast4).toBe('4567');
    expect(result.nationalIdEncrypted).toBeUndefined();
    expect(result.nationalIdHash).toBeUndefined();
    expect(JSON.stringify(result)).not.toContain('30201011234567');
  });
});
