import { BadRequestException, ConflictException, ForbiddenException, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import { PolicyAcknowledgementType, PurchaseInvoiceStatus, ShipmentCategory } from '@prisma/client';
import * as fs from 'fs';
import { NotificationsService } from '../notifications/notifications.service';
import { OrderEventsService } from '../order-events/order-events.service';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.module';
import { OrdersService } from './orders.service';
import { ChatService } from '../firebase/chat.service';
import * as proofUpload from './proof-upload';

describe('OrdersService wallet rules', () => {
  const tx = {
    order: { findUnique: jest.fn(), updateMany: jest.fn(), update: jest.fn(), create: jest.fn() },
    orderEvent: { create: jest.fn().mockResolvedValue({ id: 'e1' }) },
    orderProof: { findFirst: jest.fn(), create: jest.fn() },
    orderSkip: { deleteMany: jest.fn(), upsert: jest.fn() },
    purchaseInvoice: { findUnique: jest.fn(), create: jest.fn(), updateMany: jest.fn() },
    captainProfile: { findUnique: jest.fn(), update: jest.fn() },
    pricingSettings: { upsert: jest.fn() },
    wallet: { updateMany: jest.fn(), update: jest.fn() },
    walletTransaction: { create: jest.fn() },
    user: { findUnique: jest.fn() },
  };
  const prisma = {
    $transaction: jest.fn(async (callback: any) => callback(tx)),
    order: { findUnique: jest.fn(), updateMany: jest.fn(), update: jest.fn(), findMany: jest.fn() },
    orderEvent: { findMany: jest.fn() },
    orderProof: { findFirst: jest.fn(), create: jest.fn(), findUnique: jest.fn(), findMany: jest.fn() },
    orderSkip: { upsert: jest.fn() },
    purchaseInvoice: { findUnique: jest.fn() },
    pricingSettings: { upsert: jest.fn() },
    captainProfile: { findUnique: jest.fn(), update: jest.fn() },
    wallet: { findUnique: jest.fn() },
    user: { findUnique: jest.fn() },
  };
  const redis = { nearbyCaptains: jest.fn(), updateCaptainLocation: jest.fn() };
  const notifications = { create: jest.fn().mockResolvedValue({ id: 'n1' }) };
  const policies = { hasAcknowledgement: jest.fn().mockResolvedValue({ id: 'ack1' }) };
  const chat = { createChatForOrder: jest.fn(), closeChatForOrder: jest.fn(), reassignChat: jest.fn() };
  const fcm = {
    sendTripAlert: jest.fn().mockResolvedValue(true),
    notifyEligibleCaptains: jest.fn().mockResolvedValue(0),
    cancelTripAlert: jest.fn().mockResolvedValue(undefined),
    registerFcmToken: jest.fn().mockResolvedValue(undefined),
    clearFcmToken: jest.fn().mockResolvedValue(undefined),
  };
  const orderEvents = new OrderEventsService(prisma as unknown as PrismaService);

  const service = new OrdersService(
    prisma as unknown as PrismaService,
    redis as unknown as RedisService,
    notifications as unknown as NotificationsService,
    orderEvents,
    policies as any,
    chat as any,
    fcm as any,
  );

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.$transaction.mockImplementation(async (callback: any) => callback(tx));
    tx.pricingSettings.upsert.mockResolvedValue({ minimumWalletBalance: 0 });
    prisma.pricingSettings.upsert.mockResolvedValue({ basePrice: 30, pricePerKm: 8, commissionPercent: 10, minimumWalletBalance: 0, disabledCategories: [], minRadiusKm: 2, maxRadiusKm: 15 });
    prisma.user.findUnique.mockResolvedValue({ phone: '+201000000000' });
    tx.user.findUnique.mockResolvedValue({ phone: '+201000000000' });
    policies.hasAcknowledgement.mockResolvedValue({ id: 'ack1' });
  });

  const acceptedOrder = {
    id: 'o1',
    reference: 'WS-1',
    clientId: 'client1',
    captainId: 'cap1',
    status: 'ACCEPTED',
    commission: 15,
  };

  it('reserves commission atomically when a captain accepts', async () => {
    tx.order.findUnique
      .mockResolvedValueOnce({ id: 'o1', status: 'SEARCHING_CAPTAIN', captainId: null, commission: 15 })
      .mockResolvedValueOnce({ ...acceptedOrder, status: 'ACCEPTED' });
    tx.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    tx.wallet.updateMany.mockResolvedValue({ count: 1 });
    tx.order.updateMany.mockResolvedValue({ count: 1 });

    await service.accept('o1', 'cap1');

    expect(tx.wallet.updateMany).toHaveBeenCalled();
    expect(tx.walletTransaction.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ userId: 'cap1', type: 'ORDER_COMMISSION' }),
    });
    expect(tx.orderSkip.deleteMany).toHaveBeenCalledWith({ where: { orderId: 'o1' } });
    expect(notifications.create).toHaveBeenCalledWith(
      'client1',
      expect.any(String),
      expect.any(String),
      'ORDER',
      { orderId: 'o1' },
    );
  });

  it('rejects acceptance with insufficient wallet balance', async () => {
    tx.order.findUnique.mockResolvedValue({ id: 'o1', status: 'SEARCHING_CAPTAIN', captainId: null, commission: 50 });
    tx.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    tx.wallet.updateMany.mockResolvedValue({ count: 0 });

    await expect(service.accept('o1', 'cap1')).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(tx.order.updateMany).not.toHaveBeenCalled();
  });

  it('blocks a captain without current terms before touching the wallet', async () => {
    tx.order.findUnique.mockResolvedValue({ id: 'o1', status: 'SEARCHING_CAPTAIN', captainId: null, commission: 15, category: 'PACKAGE' });
    tx.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    policies.hasAcknowledgement.mockResolvedValueOnce(null);

    await expect(service.accept('o1', 'cap1')).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'ACK_REQUIRED', type: PolicyAcknowledgementType.TERMS_CAPTAIN }),
    });
    expect(tx.wallet.updateMany).not.toHaveBeenCalled();
    expect(tx.walletTransaction.create).not.toHaveBeenCalled();
  });

  it('blocks a sensitive-category order without its order-scoped acknowledgement', async () => {
    tx.order.findUnique.mockResolvedValue({ id: 'o1', status: 'SEARCHING_CAPTAIN', captainId: null, commission: 15, category: ShipmentCategory.FOOD });
    tx.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    policies.hasAcknowledgement.mockResolvedValueOnce({ id: 'terms' }).mockResolvedValueOnce(null);

    await expect(service.accept('o1', 'cap1')).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'ACK_REQUIRED', type: PolicyAcknowledgementType.SENSITIVE_CATEGORY }),
    });
    expect(tx.wallet.updateMany).not.toHaveBeenCalled();
  });

  it('reports a conflict when the order was taken between feed and accept', async () => {
    tx.order.findUnique.mockResolvedValue({ id: 'o1', status: 'SEARCHING_CAPTAIN', captainId: null, commission: 15, category: 'PACKAGE' });
    tx.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    tx.wallet.updateMany.mockResolvedValue({ count: 1 });
    tx.order.updateMany.mockResolvedValue({ count: 0 });

    await expect(service.accept('o1', 'cap1')).rejects.toBeInstanceOf(ConflictException);
    expect(tx.walletTransaction.create).not.toHaveBeenCalled();
  });

  describe('available orders feed', () => {
    it('returns only orders inside the captain radius with the distance attached', async () => {
      prisma.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE', isOnline: true, serviceRadiusKm: 5 });
      prisma.captainProfile.update.mockResolvedValue({});
      prisma.order.findMany.mockResolvedValue([
        { id: 'near', pickupLatitude: 30.05, pickupLongitude: 31.24 },
        { id: 'far', pickupLatitude: 30.3, pickupLongitude: 31.5 },
      ]);

      const result = await service.available('cap1', 30.0444, 31.2357);

      expect(prisma.order.findMany).toHaveBeenCalledWith(expect.objectContaining({
        where: expect.objectContaining({
          captainId: null,
          skips: { none: { captainId: 'cap1' } },
          status: { in: ['PENDING', 'SEARCHING_CAPTAIN'] },
        }),
      }));
      expect(result.map((order: any) => order.id)).toEqual(['near']);
      expect(result[0].distanceToPickupKm).toBeLessThan(5);
      expect(prisma.captainProfile.update).toHaveBeenCalledWith(expect.objectContaining({
        where: { userId: 'cap1' },
        data: expect.objectContaining({ lastLat: 30.0444, lastLng: 31.2357 }),
      }));
    });

    it('returns an empty feed while the captain is offline', async () => {
      prisma.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE', isOnline: false, serviceRadiusKm: 10 });

      await expect(service.available('cap1', 30, 31)).resolves.toEqual([]);
      expect(prisma.order.findMany).not.toHaveBeenCalled();
    });

    it('returns no orders when the wallet is below the configured minimum', async () => {
      prisma.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE', isOnline: true, serviceRadiusKm: 10 });
      prisma.wallet.findUnique.mockResolvedValue({ balance: 49 });
      prisma.pricingSettings.upsert.mockResolvedValue({ minimumWalletBalance: 50, minRadiusKm: 2, maxRadiusKm: 15 });
      prisma.captainProfile.update.mockResolvedValue({});

      await expect(service.available('cap1', 30, 31)).resolves.toEqual([]);
      expect(prisma.order.findMany).not.toHaveBeenCalled();
    });

    it('blocks captains whose account is not approved', async () => {
      prisma.captainProfile.findUnique.mockResolvedValue({ status: 'PENDING', isOnline: true, serviceRadiusKm: 10 });

      await expect(service.available('cap1', 30, 31)).rejects.toBeInstanceOf(ForbiddenException);
      expect(prisma.order.findMany).not.toHaveBeenCalled();
    });

    it('falls back to the configured maximum radius when the captain has none', async () => {
      prisma.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE', isOnline: true, serviceRadiusKm: 0 });
      prisma.captainProfile.update.mockResolvedValue({});
      prisma.order.findMany.mockResolvedValue([{ id: 'mid', pickupLatitude: 30.09, pickupLongitude: 31.29 }]);

      const result = await service.available('cap1', 30.0444, 31.2357);

      expect(result.map((order: any) => order.id)).toEqual(['mid']);
    });
  });

  describe('skipping orders', () => {
    it('records a skip idempotently for an available order', async () => {
      prisma.order.findUnique.mockResolvedValue({ id: 'o1', captainId: null, status: 'SEARCHING_CAPTAIN' });
      prisma.orderSkip.upsert.mockResolvedValue({ id: 's1' });

      await expect(service.skip('o1', 'cap1')).resolves.toEqual({ skipped: true });
      expect(prisma.orderSkip.upsert).toHaveBeenCalledWith({
        where: { orderId_captainId: { orderId: 'o1', captainId: 'cap1' } },
        update: {},
        create: { orderId: 'o1', captainId: 'cap1' },
      });
    });

    it('cannot skip an order that was already taken', async () => {
      prisma.order.findUnique.mockResolvedValue({ id: 'o1', captainId: 'cap2', status: 'ACCEPTED' });

      await expect(service.skip('o1', 'cap1')).rejects.toBeInstanceOf(ConflictException);
      expect(prisma.orderSkip.upsert).not.toHaveBeenCalled();
    });

    it('cannot skip an unknown order', async () => {
      prisma.order.findUnique.mockResolvedValue(null);

      await expect(service.skip('missing', 'cap1')).rejects.toBeInstanceOf(NotFoundException);
      expect(prisma.orderSkip.upsert).not.toHaveBeenCalled();
    });
  });

  describe('server-side expiry of stale searches', () => {
    it('cancels an expired search with a SYSTEM event and a client notification', async () => {
      prisma.order.findMany.mockResolvedValue([
        { id: 'o1', reference: 'WS-9', clientId: 'client1', status: 'SEARCHING_CAPTAIN' },
      ]);
      tx.order.updateMany.mockResolvedValue({ count: 1 });

      const result = await service.expireStaleSearches();

      expect(result).toEqual({ checked: 1, expired: 1 });
      expect(tx.order.updateMany).toHaveBeenCalledWith(expect.objectContaining({
        where: expect.objectContaining({ id: 'o1', captainId: null }),
        data: { status: 'CANCELLED' },
      }));
      expect(tx.orderEvent.create).toHaveBeenCalledWith(expect.objectContaining({
        data: expect.objectContaining({ actorRole: 'SYSTEM' }),
      }));
      expect(notifications.create).toHaveBeenCalledWith(
        'client1',
        expect.any(String),
        expect.any(String),
        'ORDER',
        { orderId: 'o1' },
      );
    });

    it('ignores orders another cycle already cancelled', async () => {
      prisma.order.findMany.mockResolvedValue([
        { id: 'o1', reference: 'WS-9', clientId: 'client1', status: 'SEARCHING_CAPTAIN' },
      ]);
      tx.order.updateMany.mockResolvedValue({ count: 0 });

      const result = await service.expireStaleSearches();

      expect(result.expired).toBe(0);
      expect(tx.orderEvent.create).not.toHaveBeenCalled();
      expect(notifications.create).not.toHaveBeenCalled();
    });
  });

  it('requires a client category acknowledgement before creating a sensitive order', async () => {
    policies.hasAcknowledgement.mockResolvedValueOnce(null);
    await expect(service.create('client1', {
      pickupLabel: 'A', pickupLatitude: 30, pickupLongitude: 31,
      deliveryLabel: 'B', deliveryLatitude: 30.1, deliveryLongitude: 31.1,
      category: ShipmentCategory.MEDICINES, description: 'Medicine', recipientName: 'R', recipientPhone: '+201000000000',
    })).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'ACK_REQUIRED', type: PolicyAcknowledgementType.SENSITIVE_CATEGORY }),
    });
    expect(tx.order.create).not.toHaveBeenCalled();
  });

  it('rejects a temporarily disabled category before quoting', async () => {
    prisma.pricingSettings.upsert.mockResolvedValue({ disabledCategories: [ShipmentCategory.FOOD] });
    await expect(service.create('client1', {
      pickupLabel: 'A', pickupLatitude: 30, pickupLongitude: 31,
      deliveryLabel: 'B', deliveryLatitude: 30.1, deliveryLongitude: 31.1,
      category: ShipmentCategory.FOOD, description: 'Groceries', recipientName: 'R', recipientPhone: '+201000000000',
    })).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.pricingSettings.upsert).toHaveBeenCalledTimes(1);
  });

  it('lets a client cancel an unassigned order with no money movement', async () => {
    tx.order.findUnique.mockResolvedValue({ id: 'o1', clientId: 'client1', captainId: null, status: 'SEARCHING_CAPTAIN' });
    tx.order.update.mockResolvedValue({ id: 'o1', status: 'CANCELLED' });

    await service.cancel('o1', 'client1');

    expect(tx.order.update).toHaveBeenCalledWith({ where: { id: 'o1' }, data: { status: 'CANCELLED' } });
    expect(tx.wallet.update).not.toHaveBeenCalled();
    expect(tx.walletTransaction.create).not.toHaveBeenCalled();
  });

  it('refunds the reserved commission when a client cancels after accept', async () => {
    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder });
    tx.order.update.mockResolvedValue({ ...acceptedOrder, status: 'CANCELLED' });

    await service.cancel('o1', 'client1');

    expect(tx.wallet.update).toHaveBeenCalledWith({
      where: { userId: 'cap1' },
      data: { balance: { increment: expect.anything() } },
    });
    expect(tx.walletTransaction.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ userId: 'cap1', type: 'COMMISSION_REFUND' }),
    });
    expect(notifications.create).toHaveBeenCalledWith('cap1', expect.any(String), expect.any(String), 'ORDER', {
      orderId: 'o1',
    });
  });

  it('blocks client cancellation after pickup', async () => {
    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder, status: 'PICKED_UP' });

    await expect(service.cancel('o1', 'client1')).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(tx.order.update).not.toHaveBeenCalled();
  });

  it('lets a captain release an order back to the pool with a refund', async () => {
    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder });
    tx.order.update.mockResolvedValue({ ...acceptedOrder, captainId: null, status: 'SEARCHING_CAPTAIN' });

    await service.release('o1', 'cap1');

    expect(tx.order.update).toHaveBeenCalledWith({
      where: { id: 'o1' },
      data: { captainId: null, status: 'SEARCHING_CAPTAIN', acceptedAt: null },
    });
    expect(tx.walletTransaction.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ userId: 'cap1', type: 'COMMISSION_REFUND' }),
    });
    expect(notifications.create).toHaveBeenCalledWith('client1', expect.any(String), expect.any(String), 'ORDER', {
      orderId: 'o1',
    });
  });

  it('blocks captain release after pickup', async () => {
    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder, status: 'ON_THE_WAY' });

    await expect(service.release('o1', 'cap1')).rejects.toBeInstanceOf(UnprocessableEntityException);
  });

  it('finalizes commission on completion without further wallet movement', async () => {
    tx.order.updateMany.mockResolvedValue({ count: 1 });
    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder, status: 'COMPLETED' });

    await service.complete('o1', 'client1');

    expect(tx.captainProfile.update).toHaveBeenCalledWith({
      where: { userId: 'cap1' },
      data: { totalTrips: { increment: 1 } },
    });
    // Held commission becomes revenue: no credit back to the captain.
    expect(tx.wallet.update).not.toHaveBeenCalled();
    expect(notifications.create).toHaveBeenCalledWith('cap1', expect.any(String), expect.any(String), 'ORDER', {
      orderId: 'o1',
    });
  });

  it('only completes delivered orders', async () => {
    tx.order.updateMany.mockResolvedValue({ count: 0 });

    await expect(service.complete('o1', 'client1')).rejects.toBeInstanceOf(UnprocessableEntityException);
  });

  it('records an event when an order is created', async () => {
    prisma.pricingSettings.upsert.mockResolvedValue({ basePrice: 30, pricePerKm: 8, commissionPercent: 10, minimumWalletBalance: 0 });
    tx.order.create.mockImplementation(async ({ data }: any) => ({ id: 'o9', ...data }));
    await service.create('client1', {
      pickupLabel: 'A', pickupLatitude: 30, pickupLongitude: 31,
      deliveryLabel: 'B', deliveryLatitude: 30.1, deliveryLongitude: 31.1,
      category: 'PACKAGE' as any, description: 'Box', recipientName: 'R', recipientPhone: '+201000000000',
    });

    expect(tx.orderEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        orderId: 'o9', fromStatus: null, toStatus: 'SEARCHING_CAPTAIN',
        actorId: 'client1', actorRole: 'CLIENT',
      }),
    });
  });

  const newOrderPayload = {
    pickupLabel: 'A', pickupLatitude: 30, pickupLongitude: 31,
    deliveryLabel: 'B', deliveryLatitude: 30.1, deliveryLongitude: 31.1,
    category: 'PACKAGE' as any, description: 'Box', recipientName: 'R', recipientPhone: '+201000000000',
  };

  const mockCreatedOrder = () => {
    tx.order.create.mockImplementation(async ({ data }: any) => ({
      id: 'o9', reference: 'WS-9', status: 'SEARCHING_CAPTAIN',
      pickupLabel: data.pickupLabel, deliveryLabel: data.deliveryLabel,
      category: data.category, price: 100, distanceKm: 5,
      pickupLatitude: data.pickupLatitude, pickupLongitude: data.pickupLongitude,
    }));
  };

  it('notifies eligible captains only after the new order is committed', async () => {
    mockCreatedOrder();
    let transactionDone = false;
    let doneAtNotify: boolean | null = null;
    prisma.$transaction.mockImplementationOnce(async (callback: any) => {
      const result = await callback(tx);
      transactionDone = true;
      return result;
    });
    fcm.notifyEligibleCaptains.mockImplementationOnce(async () => {
      doneAtNotify = transactionDone;
      return 0;
    });

    const order = await service.create('client1', newOrderPayload);

    expect(order.id).toBe('o9');
    expect(fcm.notifyEligibleCaptains).toHaveBeenCalledWith('o9');
    expect(doneAtNotify).toBe(true);
  });

  it('does not fail or change the order when FCM notification rejects', async () => {
    mockCreatedOrder();
    fcm.notifyEligibleCaptains.mockRejectedValueOnce(new Error('fcm unavailable'));

    const order = await service.create('client1', newOrderPayload);

    expect(order.status).toBe('SEARCHING_CAPTAIN');
    expect(tx.order.update).not.toHaveBeenCalled();
    expect(tx.order.updateMany).not.toHaveBeenCalled();
  });

  it('sends a cancel alert when a client cancels an assigned order', async () => {
    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder });
    tx.order.update.mockResolvedValue({ ...acceptedOrder, status: 'CANCELLED' });

    await service.cancel('o1', 'client1');

    expect(fcm.cancelTripAlert).toHaveBeenCalledWith('o1');
  });

  it('rejects order creation when the client phone is missing', async () => {
    prisma.user.findUnique.mockResolvedValueOnce({ phone: null });
    await expect(service.create('client1', {
      pickupLabel: 'A', pickupLatitude: 30, pickupLongitude: 31,
      deliveryLabel: 'B', deliveryLatitude: 30.1, deliveryLongitude: 31.1,
      category: 'PACKAGE' as any, description: 'Box', recipientName: 'R', recipientPhone: '+201000000000',
    })).rejects.toMatchObject({
      status: 403,
      response: expect.objectContaining({ code: 'PROFILE_INCOMPLETE', missing: ['phone'] }),
    });
    expect(tx.order.create).not.toHaveBeenCalled();
  });

  it('rejects acceptance when the captain phone is missing', async () => {
    tx.order.findUnique.mockResolvedValue({ id: 'o1', status: 'SEARCHING_CAPTAIN', captainId: null, commission: 15 });
    tx.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    tx.user.findUnique.mockResolvedValueOnce({ phone: '  ' });
    await expect(service.accept('o1', 'cap1')).rejects.toMatchObject({
      status: 403,
      response: expect.objectContaining({ code: 'PROFILE_INCOMPLETE' }),
    });
    expect(tx.wallet.updateMany).not.toHaveBeenCalled();
  });

  it('records an event when a captain accepts', async () => {
    tx.order.findUnique
      .mockResolvedValueOnce({ id: 'o1', status: 'SEARCHING_CAPTAIN', captainId: null, commission: 15 })
      .mockResolvedValueOnce({ ...acceptedOrder, status: 'ACCEPTED' });
    tx.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    tx.wallet.updateMany.mockResolvedValue({ count: 1 });
    tx.order.updateMany.mockResolvedValue({ count: 1 });

    await service.accept('o1', 'cap1');

    expect(tx.orderEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        orderId: 'o1', fromStatus: 'SEARCHING_CAPTAIN', toStatus: 'ACCEPTED',
        actorId: 'cap1', actorRole: 'CAPTAIN',
      }),
    });
  });

  it('records an event on trip status transition', async () => {
    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder });
    tx.order.update.mockImplementation(async ({ data }: any) => ({ ...acceptedOrder, ...data }));

    await service.transition('o1', 'cap1', 'ARRIVED_AT_PICKUP' as any);

    expect(tx.orderEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        orderId: 'o1', fromStatus: 'ACCEPTED', toStatus: 'ARRIVED_AT_PICKUP',
        actorId: 'cap1', actorRole: 'CAPTAIN',
      }),
    });
  });

  it('rejects direct PATCH jumps that require photo proof', async () => {
    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder, status: 'ARRIVED_AT_PICKUP' });

    await expect(service.transition('o1', 'cap1', 'PICKED_UP' as any)).rejects.toBeInstanceOf(
      UnprocessableEntityException,
    );
    expect(tx.order.update).not.toHaveBeenCalled();

    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder, status: 'ON_THE_WAY' });

    await expect(service.transition('o1', 'cap1', 'DELIVERED' as any)).rejects.toBeInstanceOf(
      UnprocessableEntityException,
    );
    expect(tx.order.update).not.toHaveBeenCalled();
  });

  it('records an event on client cancellation', async () => {
    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder });
    tx.order.update.mockResolvedValue({ ...acceptedOrder, status: 'CANCELLED' });

    await service.cancel('o1', 'client1');

    expect(tx.orderEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        orderId: 'o1', fromStatus: 'ACCEPTED', toStatus: 'CANCELLED',
        actorId: 'client1', actorRole: 'CLIENT',
      }),
    });
  });

  it('records an event on completion and on captain release', async () => {
    tx.order.updateMany.mockResolvedValue({ count: 1 });
    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder, status: 'COMPLETED' });

    await service.complete('o1', 'client1');
    expect(tx.orderEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        orderId: 'o1', fromStatus: 'DELIVERED', toStatus: 'COMPLETED',
        actorId: 'client1', actorRole: 'CLIENT',
      }),
    });

    jest.clearAllMocks();
    prisma.$transaction.mockImplementation(async (callback: any) => callback(tx));
    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder });
    tx.order.update.mockResolvedValue({ ...acceptedOrder, captainId: null, status: 'SEARCHING_CAPTAIN' });

    await service.release('o1', 'cap1');
    expect(tx.orderEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        orderId: 'o1', fromStatus: 'ACCEPTED', toStatus: 'SEARCHING_CAPTAIN',
        actorId: 'cap1', actorRole: 'CAPTAIN',
      }),
    });
  });

  it('leaves no event behind when the transaction fails', async () => {
    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder });
    tx.order.update.mockRejectedValue(new Error('db down'));

    await expect(service.transition('o1', 'cap1', 'ARRIVED_AT_PICKUP' as any)).rejects.toThrow('db down');
    expect(tx.orderEvent.create).not.toHaveBeenCalled();
  });

  it('shows the timeline to the owner without actor ids', async () => {
    prisma.order.findUnique.mockResolvedValue({ ...acceptedOrder, client: {}, captain: {} });
    prisma.orderEvent.findMany.mockResolvedValue([
      { id: 'e1', orderId: 'o1', fromStatus: null, toStatus: 'SEARCHING_CAPTAIN', actorId: 'client1', actorRole: 'CLIENT', note: 'Order created', createdAt: new Date() },
    ]);

    const events = await service.eventsForUser('o1', { id: 'client1', role: 'CLIENT' as any });

    expect(events).toHaveLength(1);
    expect(events[0]).not.toHaveProperty('actorId');
    expect(events[0]).toMatchObject({ toStatus: 'SEARCHING_CAPTAIN', actorRole: 'CLIENT' });
  });

  it('forbids strangers from reading the timeline', async () => {
    prisma.order.findUnique.mockResolvedValue({ ...acceptedOrder, client: {}, captain: {} });

    await expect(service.eventsForUser('o1', { id: 'stranger', role: 'CLIENT' as any })).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    expect(prisma.orderEvent.findMany).not.toHaveBeenCalled();
  });

  const arrivedOrder = { ...acceptedOrder, status: 'ARRIVED_AT_PICKUP' };
  const onTheWayOrder = { ...acceptedOrder, status: 'ON_THE_WAY' };
  const pngPhoto = {
    buffer: Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00]),
    size: 9,
  };

  it('submits pickup proof and moves to PICKED_UP', async () => {
    tx.order.findUnique.mockResolvedValue({ ...arrivedOrder });
    tx.orderProof.findFirst.mockResolvedValue(null);
    jest.spyOn(proofUpload, 'saveProofPhoto').mockResolvedValue({ relativePath: 'proofs/o1/x.jpg', mimeType: 'image/jpeg' });
    tx.orderProof.create.mockImplementation(async ({ data }: any) => ({ id: 'p1', ...data }));
    tx.order.update.mockImplementation(async ({ data }: any) => ({ ...arrivedOrder, ...data }));

    await service.submitPickupProof('o1', 'cap1', pngPhoto, 'Box handed over');

    expect(tx.orderProof.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ orderId: 'o1', type: 'PICKUP', photoPath: 'proofs/o1/x.jpg', capturedById: 'cap1' }),
    });
    expect(tx.order.update).toHaveBeenCalledWith({
      where: { id: 'o1' },
      data: expect.objectContaining({ status: 'PICKED_UP' }),
    });
    expect(tx.orderEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ fromStatus: 'ARRIVED_AT_PICKUP', toStatus: 'PICKED_UP', actorRole: 'CAPTAIN' }),
    });
    expect(notifications.create).toHaveBeenCalledWith('client1', expect.any(String), expect.any(String), 'ORDER', {
      orderId: 'o1',
    });
  });

  it('rejects pickup proof in the wrong state, by a stranger captain, or twice', async () => {
    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder, status: 'ACCEPTED' });
    tx.orderProof.findFirst.mockResolvedValue(null);

    await expect(service.submitPickupProof('o1', 'cap1')).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(tx.orderProof.create).not.toHaveBeenCalled();

    tx.order.findUnique.mockResolvedValue({ ...arrivedOrder, captainId: 'capX' });
    await expect(service.submitPickupProof('o1', 'cap1')).rejects.toBeInstanceOf(ForbiddenException);

    tx.order.findUnique.mockResolvedValue({ ...arrivedOrder });
    tx.orderProof.findFirst.mockResolvedValue({ id: 'p1' });
    await expect(service.submitPickupProof('o1', 'cap1')).rejects.toBeInstanceOf(ConflictException);
    expect(tx.order.update).not.toHaveBeenCalled();
  });

  it('submits delivery proof and moves to DELIVERED', async () => {
    tx.order.findUnique.mockResolvedValue({ ...onTheWayOrder });
    tx.orderProof.findFirst.mockResolvedValue(null);
    tx.orderProof.create.mockImplementation(async ({ data }: any) => ({ id: 'p2', ...data }));
    tx.order.update.mockImplementation(async ({ data }: any) => ({ ...onTheWayOrder, ...data }));

    await service.submitDeliveryProof('o1', 'cap1');

    expect(tx.orderProof.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ orderId: 'o1', type: 'DELIVERY', photoPath: null, capturedById: 'cap1' }),
    });
    expect(tx.order.update).toHaveBeenCalledWith({
      where: { id: 'o1' },
      data: expect.objectContaining({ status: 'DELIVERED' }),
    });
    expect(tx.orderEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ fromStatus: 'ON_THE_WAY', toStatus: 'DELIVERED', actorRole: 'CAPTAIN' }),
    });
  });

  it('rejects delivery proof in the wrong state or by a stranger captain', async () => {
    tx.order.findUnique.mockResolvedValue({ ...acceptedOrder, status: 'PICKED_UP' });
    tx.orderProof.findFirst.mockResolvedValue(null);

    await expect(service.submitDeliveryProof('o1', 'cap1')).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(tx.orderProof.create).not.toHaveBeenCalled();

    tx.order.findUnique.mockResolvedValue({ ...onTheWayOrder, captainId: 'capX' });
    await expect(service.submitDeliveryProof('o1', 'cap1')).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('changes nothing when proof persistence fails', async () => {
    tx.order.findUnique.mockResolvedValue({ ...arrivedOrder });
    tx.orderProof.findFirst.mockResolvedValue(null);
    tx.orderProof.create.mockRejectedValue(new Error('db down'));

    await expect(service.submitPickupProof('o1', 'cap1')).rejects.toThrow('db down');
    expect(tx.order.update).not.toHaveBeenCalled();
    expect(tx.orderEvent.create).not.toHaveBeenCalled();
  });

  it('aborts the whole submission when the status move fails', async () => {
    tx.order.findUnique.mockResolvedValue({ ...arrivedOrder });
    tx.orderProof.findFirst.mockResolvedValue(null);
    tx.orderProof.create.mockImplementation(async ({ data }: any) => ({ id: 'p1', ...data }));
    tx.order.update.mockRejectedValue(new Error('db down'));

    await expect(service.submitPickupProof('o1', 'cap1')).rejects.toThrow('db down');
    // In production the surrounding transaction rolls the proof row back too.
    expect(tx.orderEvent.create).not.toHaveBeenCalled();
  });

  it('lists proofs to the owner without internal paths, and forbids strangers', async () => {
    prisma.order.findUnique.mockResolvedValue({ ...acceptedOrder, client: {}, captain: {} });
    prisma.orderProof.findMany.mockResolvedValue([
      { id: 'p1', orderId: 'o1', type: 'PICKUP', note: null, capturedById: 'cap1', photoPath: 'proofs/o1/x.jpg', createdAt: new Date() },
    ]);

    const proofs = await service.proofsForUser('o1', { id: 'client1', role: 'CLIENT' as any });
    expect(proofs).toHaveLength(1);
    expect(proofs[0]).not.toHaveProperty('photoPath');
    expect(proofs[0]).toMatchObject({ type: 'PICKUP', hasPhoto: true });

    await expect(service.proofsForUser('o1', { id: 'stranger', role: 'CLIENT' as any })).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('streams proof photos to authorized parties only', async () => {
    prisma.order.findUnique.mockResolvedValue({ ...acceptedOrder, client: {}, captain: {} });
    prisma.orderProof.findUnique.mockResolvedValue({
      id: 'p1', orderId: 'o1', type: 'PICKUP', photoPath: 'proofs/o1/x.jpg',
    });
    jest.spyOn(fs, 'existsSync').mockReturnValue(true);

    const file = await service.proofPhotoForUser('o1', 'p1', { id: 'cap1', role: 'CAPTAIN' as any });
    expect(file.path.endsWith('x.jpg')).toBe(true);
    expect(file.mimeType).toBe('image/jpeg');

    await expect(
      service.proofPhotoForUser('o1', 'p1', { id: 'stranger', role: 'CLIENT' as any }),
    ).rejects.toBeInstanceOf(ForbiddenException);

    prisma.orderProof.findUnique.mockResolvedValue({ id: 'p1', orderId: 'other', type: 'PICKUP', photoPath: 'proofs/other/x.jpg' });
    await expect(
      service.proofPhotoForUser('o1', 'p1', { id: 'client1', role: 'CLIENT' as any }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('serves proof photos stored with Windows separators', async () => {
    prisma.order.findUnique.mockResolvedValue({ ...acceptedOrder, client: {}, captain: {} });
    prisma.orderProof.findUnique.mockResolvedValue({
      id: 'p1', orderId: 'o1', type: 'PICKUP', photoPath: 'proofs\\o1\\x.jpg',
    });
    jest.spyOn(fs, 'existsSync').mockReturnValue(true);

    const file = await service.proofPhotoForUser('o1', 'p1', { id: 'cap1', role: 'CAPTAIN' as any });
    expect(file.path.endsWith('x.jpg')).toBe(true);
    expect(file.mimeType).toBe('image/jpeg');
  });

  it('serves invoice photos stored with Windows separators', async () => {
    prisma.order.findUnique.mockResolvedValue({ ...invoiceOrder, client: {}, captain: {} });
    prisma.purchaseInvoice.findUnique.mockResolvedValue({ photoPath: 'proofs\\o1\\inv.png' });
    jest.spyOn(fs, 'existsSync').mockReturnValue(true);

    const file = await service.invoicePhotoForUser('o1', { id: 'client1', role: 'CLIENT' as any });
    expect(file.mimeType).toBe('image/png');
  });

  const invoiceOrder = {
    id: 'o1', clientId: 'client1', captainId: 'cap1', status: 'PICKED_UP',
    category: ShipmentCategory.PURCHASES, estimatedBudget: 250,
  };

  it('rejects invoice upload by an unassigned captain or for an unsupported category', async () => {
    tx.order.findUnique.mockResolvedValue({ ...invoiceOrder, captainId: 'capX' });
    await expect(service.submitInvoice('o1', 'cap1', { amount: 100 }, pngPhoto)).rejects.toBeInstanceOf(ForbiddenException);

    tx.order.findUnique.mockResolvedValue({ ...invoiceOrder, category: ShipmentCategory.PACKAGE });
    await expect(service.submitInvoice('o1', 'cap1', { amount: 100 }, pngPhoto)).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(tx.purchaseInvoice.create).not.toHaveBeenCalled();
  });

  it('rejects invalid amounts, budgets, duplicate invoices, and bad image bytes', async () => {
    tx.order.findUnique.mockResolvedValue({ ...invoiceOrder });
    await expect(service.submitInvoice('o1', 'cap1', { amount: -1 }, pngPhoto)).rejects.toBeInstanceOf(BadRequestException);
    await expect(service.submitInvoice('o1', 'cap1', { amount: 0 }, pngPhoto)).rejects.toBeInstanceOf(BadRequestException);
    await expect(service.submitInvoice('o1', 'cap1', { amount: 251 }, pngPhoto)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'BUDGET_EXCEEDED' }),
    });
    expect(tx.purchaseInvoice.create).not.toHaveBeenCalled();

    tx.purchaseInvoice.findUnique.mockResolvedValue({ id: 'existing' });
    await expect(service.submitInvoice('o1', 'cap1', { amount: 100 }, pngPhoto)).rejects.toBeInstanceOf(ConflictException);

    tx.purchaseInvoice.findUnique.mockResolvedValue(null);
    jest.restoreAllMocks();
    await expect(service.submitInvoice('o1', 'cap1', { amount: 100 }, { buffer: Buffer.from('not-image'), size: 9 }))
      .rejects.toBeInstanceOf(BadRequestException);
    await expect(service.submitInvoice('o1', 'cap1', { amount: 100 }, { buffer: pngPhoto.buffer, size: 5 * 1024 * 1024 + 1 }))
      .rejects.toBeInstanceOf(BadRequestException);
    expect(tx.purchaseInvoice.create).not.toHaveBeenCalled();
  });

  it('submits an invoice with a private photo path and records an event', async () => {
    tx.order.findUnique.mockResolvedValue({ ...invoiceOrder });
    tx.purchaseInvoice.findUnique.mockResolvedValue(null);
    tx.purchaseInvoice.create.mockImplementation(async ({ data }: any) => ({
      id: 'invoice1', ...data, status: PurchaseInvoiceStatus.SUBMITTED, createdAt: new Date(), photoPath: 'proofs/o1/random.png',
    }));
    prisma.order.findUnique.mockResolvedValue({ clientId: 'client1' });
    jest.spyOn(proofUpload, 'saveProofPhoto').mockResolvedValue({ relativePath: 'proofs/o1/random.png', mimeType: 'image/png' });

    const result = await service.submitInvoice('o1', 'cap1', { amount: 120, note: 'Receipt' }, pngPhoto);

    expect(result).not.toHaveProperty('photoPath');
    expect(result).toMatchObject({ id: 'invoice1', amount: expect.anything(), hasPhoto: true });
    expect(tx.orderEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ orderId: 'o1', fromStatus: 'PICKED_UP', toStatus: 'PICKED_UP', actorRole: 'CAPTAIN' }),
    });
    expect(notifications.create).toHaveBeenCalledWith('client1', expect.any(String), expect.any(String), 'ORDER', { orderId: 'o1' });
  });

  it('lets only the owner respond once and does not move money', async () => {
    const submitted = { id: 'invoice1', orderId: 'o1', status: PurchaseInvoiceStatus.SUBMITTED, clientRespondedAt: null, photoPath: 'proofs/o1/random.png' };
    tx.order.findUnique.mockResolvedValue({ ...invoiceOrder });
    tx.purchaseInvoice.findUnique.mockResolvedValueOnce(submitted).mockResolvedValueOnce({
      ...submitted, status: PurchaseInvoiceStatus.DISPUTED, clientRespondedAt: new Date(), clientResponseReason: 'Mismatch',
    });
    tx.purchaseInvoice.updateMany.mockResolvedValue({ count: 1 });
    prisma.order.findUnique.mockResolvedValue({ captainId: 'cap1' });

    const result = await service.respondToInvoice('o1', 'client1', { action: 'DISPUTED', reason: 'Mismatch' });

    expect(result).toMatchObject({ status: PurchaseInvoiceStatus.DISPUTED, hasPhoto: true });
    expect(tx.orderEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ actorId: 'client1', actorRole: 'CLIENT', fromStatus: 'PICKED_UP', toStatus: 'PICKED_UP' }),
    });
    expect(tx.wallet.update).not.toHaveBeenCalled();
    expect(tx.walletTransaction.create).not.toHaveBeenCalled();

    tx.order.findUnique.mockResolvedValue({ ...invoiceOrder, clientId: 'another-client' });
    await expect(service.respondToInvoice('o1', 'client1', { action: 'CONFIRMED' })).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('allows a single confirmation without a reason', async () => {
    const submitted = { id: 'invoice1', orderId: 'o1', status: PurchaseInvoiceStatus.SUBMITTED, clientRespondedAt: null, photoPath: 'proofs/o1/random.png' };
    tx.order.findUnique.mockResolvedValue({ ...invoiceOrder });
    tx.purchaseInvoice.findUnique.mockResolvedValueOnce(submitted).mockResolvedValueOnce({
      ...submitted, status: PurchaseInvoiceStatus.CONFIRMED, clientRespondedAt: new Date(),
    });
    tx.purchaseInvoice.updateMany.mockResolvedValue({ count: 1 });
    prisma.order.findUnique.mockResolvedValue({ captainId: 'cap1' });

    const result = await service.respondToInvoice('o1', 'client1', { action: 'CONFIRMED' });

    expect(result.status).toBe(PurchaseInvoiceStatus.CONFIRMED);
    tx.purchaseInvoice.findUnique.mockResolvedValue({ ...submitted, status: PurchaseInvoiceStatus.CONFIRMED });
    await expect(service.respondToInvoice('o1', 'client1', { action: 'CONFIRMED' })).rejects.toBeInstanceOf(ConflictException);
    expect(tx.purchaseInvoice.updateMany).toHaveBeenCalledTimes(1);
  });

  it('hides invoices and photos from unrelated users', async () => {
    prisma.order.findUnique.mockResolvedValue({ ...invoiceOrder, client: {}, captain: {} });
    await expect(service.invoiceForUser('o1', { id: 'stranger', role: 'CLIENT' as any })).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.purchaseInvoice.findUnique).not.toHaveBeenCalled();
  });
});
