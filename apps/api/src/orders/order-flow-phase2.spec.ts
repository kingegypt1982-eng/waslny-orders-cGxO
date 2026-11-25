import { BadRequestException, ConflictException, ForbiddenException, Logger, UnprocessableEntityException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { validate } from 'class-validator';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import { RateOrderDto } from './dto/rate-order.dto';
import { NotificationsService } from '../notifications/notifications.service';
import { OrderEventsService } from '../order-events/order-events.service';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.module';
import { OrdersService } from './orders.service';
import { ChatService } from '../firebase/chat.service';

describe('Order flow phase 2 guards, location and rating', () => {
  const tx: any = {
    order: { findUnique: jest.fn(), updateMany: jest.fn(), update: jest.fn(), create: jest.fn() },
    orderEvent: { create: jest.fn().mockResolvedValue({ id: 'e1' }) },
    orderSkip: { deleteMany: jest.fn(), upsert: jest.fn() },
    captainProfile: { findUnique: jest.fn(), update: jest.fn(), updateMany: jest.fn() },
    pricingSettings: { upsert: jest.fn() },
    wallet: { updateMany: jest.fn(), update: jest.fn() },
    walletTransaction: { create: jest.fn() },
    user: { findUnique: jest.fn() },
    orderRating: { create: jest.fn(), findUnique: jest.fn(), findFirst: jest.fn(), aggregate: jest.fn() },
  };
  const prisma: any = {
    $transaction: jest.fn(async (cb: any) => cb(tx)),
    $queryRaw: jest.fn().mockResolvedValue([]),
    $executeRaw: jest.fn().mockResolvedValue(1),
    order: { findUnique: jest.fn(), findMany: jest.fn(), updateMany: jest.fn(), create: jest.fn() },
    orderEvent: { findMany: jest.fn() },
    captainProfile: { findUnique: jest.fn(), update: jest.fn() },
    pricingSettings: { upsert: jest.fn() },
    user: { findUnique: jest.fn() },
    wallet: { findUnique: jest.fn() },
    orderRating: { findUnique: jest.fn(), findFirst: jest.fn() },
  };
  const redis: any = { updateCaptainLocation: jest.fn().mockResolvedValue(true), nearbyCaptains: jest.fn() };
  const notifications: any = { create: jest.fn().mockResolvedValue({ id: 'n1' }) };
  const chat = { createChatForOrder: jest.fn(), closeChatForOrder: jest.fn(), reassignChat: jest.fn() };
  const fcm = {
    sendTripAlert: jest.fn().mockResolvedValue(true),
    notifyEligibleCaptains: jest.fn().mockResolvedValue(0),
    cancelTripAlert: jest.fn().mockResolvedValue(undefined),
    registerFcmToken: jest.fn().mockResolvedValue(undefined),
    clearFcmToken: jest.fn().mockResolvedValue(undefined),
  };
  const orderEvents = new OrderEventsService(prisma as PrismaService);
  const policies: any = { hasAcknowledgement: jest.fn().mockResolvedValue({ id: 'ack1' }) };
  const service = new OrdersService(
    prisma as PrismaService,
    redis as RedisService,
    notifications as NotificationsService,
    orderEvents,
    policies,
    chat as any,
    fcm as any,
  );

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.$transaction.mockImplementation(async (cb: any) => cb(tx));
    prisma.$queryRaw.mockResolvedValue([]);
    prisma.$executeRaw.mockResolvedValue(1);
    prisma.pricingSettings.upsert.mockResolvedValue({ basePrice: 30, pricePerKm: 8, commissionPercent: 10, minimumWalletBalance: 0, disabledCategories: [] });
    tx.pricingSettings.upsert.mockResolvedValue({ minimumWalletBalance: 0 });
    prisma.user.findUnique.mockResolvedValue({ phone: '+201000000000' });
    tx.user.findUnique.mockResolvedValue({ phone: '+201000000000' });
    notifications.create.mockResolvedValue({ id: 'n1' });
    redis.updateCaptainLocation.mockResolvedValue(true);
    prisma.orderRating.findUnique.mockResolvedValue(null);
    prisma.orderRating.findFirst.mockResolvedValue(null);
    tx.orderRating.findUnique.mockResolvedValue(null);
    tx.orderRating.create.mockImplementation(async ({ data }: any) => ({
      id: 'r1',
      createdAt: new Date('2026-11-20T00:00:00.000Z'),
      ...data,
    }));
    tx.orderRating.aggregate.mockResolvedValue({ _avg: { stars: 4 } });
    tx.captainProfile.updateMany.mockResolvedValue({ count: 1 });
  });

  it('returns 409 on a second accept instead of debiting the wallet twice', async () => {
    tx.order.findUnique.mockResolvedValue({ id: 'o1', status: 'ACCEPTED', captainId: 'cap1', commission: 15 });
    tx.captainProfile.findUnique.mockResolvedValue({ userId: 'cap1', status: 'ACTIVE' });
    tx.wallet.updateMany.mockResolvedValue({ count: 1 });

    await expect(service.accept('o1', 'cap1')).rejects.toBeInstanceOf(ConflictException);
    expect(tx.wallet.updateMany).not.toHaveBeenCalled();
    expect(tx.walletTransaction.create).not.toHaveBeenCalled();
  });

  it('keeps the server state machine strict for direct status patches', async () => {
    tx.order.findUnique.mockResolvedValue({ id: 'o1', status: 'ACCEPTED', captainId: 'cap1' });
    await expect(service.transition('o1', 'cap1', 'DELIVERED' as any)).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(tx.order.updateMany).not.toHaveBeenCalled();
  });

  it('stores an active-trip heartbeat and mirrors it to Redis', async () => {
    prisma.order.findUnique.mockResolvedValue({ id: 'o1', status: 'ON_THE_WAY', captainId: 'cap1', clientId: 'cl1' });
    prisma.captainProfile.update.mockResolvedValue({});

    await expect(service.updateTripLocation('o1', 'cap1', 30.1, 31.2)).resolves.toEqual({ updated: true });
    expect(prisma.captainProfile.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { userId: 'cap1' }, data: expect.objectContaining({ lastLat: 30.1, lastLng: 31.2 }) }),
    );
    expect(redis.updateCaptainLocation).toHaveBeenCalledWith('cap1', 30.1, 31.2);
  });

  it('rejects heartbeats from another captain or outside an active trip', async () => {
    prisma.order.findUnique.mockResolvedValue({ id: 'o1', status: 'ON_THE_WAY', captainId: 'cap1', clientId: 'cl1' });
    await expect(service.updateTripLocation('o1', 'intruder', 30, 31)).rejects.toBeInstanceOf(ForbiddenException);
    prisma.order.findUnique.mockResolvedValue({ id: 'o1', status: 'COMPLETED', captainId: 'cap1', clientId: 'cl1' });
    await expect(service.updateTripLocation('o1', 'cap1', 30, 31)).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(prisma.captainProfile.update).not.toHaveBeenCalled();
  });

  it('exposes the live captain position only to order participants', async () => {
    prisma.order.findUnique.mockResolvedValue({ id: 'o1', status: 'ON_THE_WAY', captainId: 'cap1', clientId: 'cl1' });
    prisma.captainProfile.findUnique.mockResolvedValue({ lastLat: 30.1, lastLng: 31.2, lastSeenAt: new Date('2026-01-01T00:00:00.000Z') });

    await expect(service.tripLocationForUser('o1', { id: 'cl1', role: 'CLIENT' } as any)).resolves.toEqual(
      expect.objectContaining({ latitude: 30.1, longitude: 31.2 }),
    );
    await expect(service.tripLocationForUser('o1', { id: 'other', role: 'CLIENT' } as any)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('migrates the existing rating table in place instead of creating a parallel one', () => {
    const migration = readFileSync(
      resolve(__dirname, '../../prisma/migrations/20261120100000_migrate_order_ratings_to_stars_two_parties/migration.sql'),
      'utf8',
    );
    const schema = readFileSync(resolve(__dirname, '../../prisma/schema.prisma'), 'utf8');

    expect(migration).toContain('ALTER TABLE "OrderRating" RENAME COLUMN "score" TO "stars"');
    expect(migration).toContain('ALTER TABLE "OrderRating" RENAME COLUMN "clientId" TO "raterId"');
    expect(migration).toContain('ALTER TABLE "OrderRating" RENAME COLUMN "captainId" TO "rateeId"');
    expect(migration).not.toMatch(/DROP TABLE|CREATE TABLE "OrderRating"/i);
    expect(migration).toContain('("orderId", "raterId")');
    expect(migration).toContain('AVG("stars")');
    expect(migration).toContain('UPDATE "CaptainProfile"');
    expect(schema).toContain('@@unique([orderId, raterId])');
    expect(schema).not.toMatch(/^\s*score\s+Int/m);
  });

  it('rejects ratings outside DELIVERED/COMPLETED, including CANCELLED', async () => {
    for (const status of ['PENDING', 'ON_THE_WAY', 'CANCELLED']) {
      prisma.order.findUnique.mockResolvedValue({ id: 'o1', status, captainId: 'cap1', clientId: 'cl1' });
      await expect(
        service.rateOrder('o1', { id: 'cl1', role: 'CLIENT' } as any, { stars: 5 }),
      ).rejects.toBeInstanceOf(UnprocessableEntityException);
    }
    prisma.order.findUnique.mockResolvedValue({ id: 'o1', status: 'CANCELLED', captainId: 'cap1', clientId: 'cl1' });
    await expect(
      service.rateOrder('o1', { id: 'cl1', role: 'CLIENT' } as any, { stars: 5 }),
    ).rejects.toThrow('Cancelled orders cannot be rated');
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('accepts ratings after DELIVERED and COMPLETED', async () => {
    for (const status of ['DELIVERED', 'COMPLETED']) {
      prisma.order.findUnique.mockResolvedValue({ id: 'o1', status, captainId: 'cap1', clientId: 'cl1' });
      await expect(
        service.rateOrder('o1', { id: 'cl1', role: 'CLIENT' } as any, { stars: 5 }),
      ).resolves.toEqual(expect.objectContaining({ stars: 5 }));
    }
  });

  it('forbids a rating from a user not linked to the order', async () => {
    prisma.order.findUnique.mockResolvedValue({ id: 'o1', status: 'DELIVERED', captainId: 'cap1', clientId: 'cl1' });
    await expect(
      service.rateOrder('o1', { id: 'outsider', role: 'CLIENT' } as any, { stars: 5 }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(tx.orderRating.create).not.toHaveBeenCalled();
  });

  it('derives rateeId from the order and recomputes the captain average from an aggregate in one transaction', async () => {
    prisma.order.findUnique.mockResolvedValue({ id: 'o1', status: 'DELIVERED', captainId: 'cap1', clientId: 'cl1' });
    // The stored average (3) differs from the new rating (4): a cumulative
    // average would fail this assertion.
    tx.orderRating.aggregate.mockResolvedValue({ _avg: { stars: 3 } });

    const result = await service.rateOrder('o1', { id: 'cl1', role: 'CLIENT' } as any, {
      stars: 4,
      rateeId: 'intruder',
      comment: '  great  ',
    } as any);

    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(tx.orderRating.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ orderId: 'o1', raterId: 'cl1', rateeId: 'cap1', stars: 4, comment: 'great' }),
    });
    expect(tx.orderRating.aggregate).toHaveBeenCalledWith({ where: { rateeId: 'cap1' }, _avg: { stars: true } });
    expect(tx.captainProfile.updateMany).toHaveBeenCalledWith({
      where: { userId: 'cap1' },
      data: { rating: 3 },
    });
    expect(result).toEqual(expect.objectContaining({ rateeId: 'cap1', stars: 4 }));
  });

  it('lets the captain rate the client without touching any captain profile average', async () => {
    prisma.order.findUnique.mockResolvedValue({ id: 'o1', status: 'COMPLETED', captainId: 'cap1', clientId: 'cl1' });

    await service.rateOrder('o1', { id: 'cap1', role: 'CAPTAIN' } as any, { stars: 2 });

    expect(tx.orderRating.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ raterId: 'cap1', rateeId: 'cl1', stars: 2 }),
    });
    expect(tx.orderRating.aggregate).not.toHaveBeenCalled();
    expect(tx.captainProfile.updateMany).not.toHaveBeenCalled();
  });

  it('rejects a second rating from the same party', async () => {
    prisma.order.findUnique.mockResolvedValue({ id: 'o1', status: 'DELIVERED', captainId: 'cap1', clientId: 'cl1' });
    prisma.orderRating.findUnique.mockResolvedValue({ id: 'r0' });

    await expect(
      service.rateOrder('o1', { id: 'cl1', role: 'CLIENT' } as any, { stars: 4 }),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.orderRating.findUnique).toHaveBeenCalledWith({
      where: { orderId_raterId: { orderId: 'o1', raterId: 'cl1' } },
    });
    expect(tx.orderRating.create).not.toHaveBeenCalled();
  });

  it('maps a concurrent unique violation to a conflict', async () => {
    prisma.order.findUnique.mockResolvedValue({ id: 'o1', status: 'DELIVERED', captainId: 'cap1', clientId: 'cl1' });
    tx.orderRating.create.mockRejectedValueOnce(
      new Prisma.PrismaClientKnownRequestError('duplicate', { code: 'P2002', clientVersion: '6.19.3' }),
    );

    await expect(
      service.rateOrder('o1', { id: 'cl1', role: 'CLIENT' } as any, { stars: 4 }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('accepts the deprecated score alias and logs a warning', async () => {
    const warn = jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    prisma.order.findUnique.mockResolvedValue({ id: 'o1', status: 'DELIVERED', captainId: 'cap1', clientId: 'cl1' });

    await expect(
      service.rateOrder('o1', { id: 'cl1', role: 'CLIENT' } as any, { score: 4 } as any),
    ).resolves.toEqual(expect.objectContaining({ stars: 4 }));
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('deprecated'));
    warn.mockRestore();
  });

  it('requires stars when the deprecated alias is absent', async () => {
    prisma.order.findUnique.mockResolvedValue({ id: 'o1', status: 'DELIVERED', captainId: 'cap1', clientId: 'cl1' });
    await expect(
      service.rateOrder('o1', { id: 'cl1', role: 'CLIENT' } as any, {} as any),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('validates stars 1-5, the 500-character comment limit and a body-supplied rateeId', async () => {
    expect(await validate(Object.assign(new RateOrderDto(), { stars: 6 }))).not.toHaveLength(0);
    expect(await validate(Object.assign(new RateOrderDto(), { stars: 2.5 }))).not.toHaveLength(0);
    expect(await validate(Object.assign(new RateOrderDto(), { stars: 5, comment: 'x'.repeat(501) }))).not.toHaveLength(0);
    expect(await validate(Object.assign(new RateOrderDto(), { stars: 5, comment: 'x'.repeat(500) }))).toHaveLength(0);
    const rateeErrors = await validate(Object.assign(new RateOrderDto(), { stars: 5, rateeId: 'intruder' }));
    expect(rateeErrors.map((error) => error.property)).toContain('rateeId');
  });

  it('returns the caller own rating with a temporary score alias, or null', async () => {
    prisma.order.findUnique.mockResolvedValue({ id: 'o1', status: 'DELIVERED', captainId: 'cap1', clientId: 'cl1' });
    prisma.orderRating.findFirst.mockResolvedValue({
      id: 'r1', orderId: 'o1', raterId: 'cl1', rateeId: 'cap1', stars: 4, comment: 'ok', createdAt: new Date(),
    });

    await expect(
      service.ratingForUser('o1', { id: 'cl1', role: 'CLIENT' } as any),
    ).resolves.toEqual(expect.objectContaining({ stars: 4, score: 4 }));
    expect(prisma.orderRating.findFirst).toHaveBeenCalledWith({
      where: { orderId: 'o1', raterId: 'cl1' },
      orderBy: { createdAt: 'desc' },
    });

    prisma.orderRating.findFirst.mockResolvedValue(null);
    await expect(
      service.ratingForUser('o1', { id: 'cl1', role: 'CLIENT' } as any),
    ).resolves.toBeNull();
  });

  it('refunds the reserved commission when the client cancels before pickup', async () => {
    tx.order.findUnique.mockResolvedValue({ id: 'o1', status: 'ACCEPTED', captainId: 'cap1', clientId: 'cl1', commission: 15, reference: 'WS-1' });
    tx.order.updateMany.mockResolvedValue({ count: 1 });
    tx.wallet.update.mockResolvedValue({});
    tx.walletTransaction.create.mockResolvedValue({});

    await service.cancel('o1', 'cl1');
    expect(tx.wallet.update).toHaveBeenCalledWith({ where: { userId: 'cap1' }, data: { balance: { increment: expect.anything() } } });
    expect(tx.walletTransaction.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ type: 'COMMISSION_REFUND', userId: 'cap1' }) }),
    );
  });

  it('increments totalTrips only on client completion, with no wallet movement', async () => {
    tx.order.findUnique.mockResolvedValue({ id: 'o1', status: 'DELIVERED', captainId: 'cap1', clientId: 'cl1', reference: 'WS-1' });
    tx.order.updateMany.mockResolvedValue({ count: 1 });
    await service.complete('o1', 'cl1');

    expect(tx.captainProfile.update).toHaveBeenCalledWith({
      where: { userId: 'cap1' },
      data: { totalTrips: { increment: 1 } },
    });
    expect(tx.wallet.update).not.toHaveBeenCalled();
    expect(tx.walletTransaction.create).not.toHaveBeenCalled();
  });

  it('notifies the client on creation and the captain on acceptance', async () => {
    tx.order.create.mockImplementation(async ({ data }: any) => ({ id: 'o2', reference: 'WS-2', ...data }));
    await service.create('cl1', {
      pickupLabel: 'A', pickupLatitude: 30, pickupLongitude: 31,
      deliveryLabel: 'B', deliveryLatitude: 30.1, deliveryLongitude: 31.1,
      category: 'PACKAGE' as any, description: '', recipientName: 'R', recipientPhone: '+201000000000',
    });
    expect(notifications.create).toHaveBeenCalledWith(
      'cl1', expect.any(String), expect.any(String), 'ORDER',
      expect.objectContaining({ screen: 'ORDER_CREATED' }),
    );

    tx.order.findUnique.mockResolvedValue({ id: 'o2', status: 'SEARCHING_CAPTAIN', captainId: null, commission: 15, reference: 'WS-2' });
    tx.captainProfile.findUnique.mockResolvedValue({ userId: 'cap1', status: 'ACTIVE' });
    tx.wallet.updateMany.mockResolvedValue({ count: 1 });
    tx.order.updateMany.mockResolvedValue({ count: 1 });
    tx.order.findUnique.mockResolvedValueOnce({ id: 'o2', status: 'SEARCHING_CAPTAIN', captainId: null, commission: 15, reference: 'WS-2' });
    await service.accept('o2', 'cap1');
    expect(notifications.create).toHaveBeenCalledWith(
      'cap1', expect.any(String), expect.any(String), 'ORDER',
      expect.objectContaining({ screen: 'ORDER_ACCEPTED' }),
    );
  });
});
