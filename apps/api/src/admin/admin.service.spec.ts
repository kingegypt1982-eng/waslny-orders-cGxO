import { BadRequestException, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import * as fs from 'fs';
import { NotificationsService } from '../notifications/notifications.service';
import { OrderEventsService } from '../order-events/order-events.service';
import { PrismaService } from '../prisma/prisma.service';
import { AdminService } from './admin.service';
import { ChatService } from '../firebase/chat.service';

describe('AdminService', () => {
  const tx = {
    order: { findUnique: jest.fn(), update: jest.fn() },
    orderEvent: { create: jest.fn().mockResolvedValue({ id: 'e1' }) },
    captainProfile: { findUnique: jest.fn() },
    wallet: { updateMany: jest.fn(), update: jest.fn() },
    walletTransaction: { create: jest.fn() },
  };
  const prisma = {
    user: { count: jest.fn(), findMany: jest.fn(), update: jest.fn() },
    captainProfile: { count: jest.fn(), findMany: jest.fn(), findUnique: jest.fn(), update: jest.fn() },
    order: { count: jest.fn(), aggregate: jest.fn(), findMany: jest.fn(), findUnique: jest.fn() },
    orderEvent: { findMany: jest.fn() },
    orderProof: { findMany: jest.fn() },
    policyAcknowledgement: { findMany: jest.fn() },
    purchaseInvoice: { findUnique: jest.fn() },
    walletTransaction: { findMany: jest.fn() },
    pricingSettings: { upsert: jest.fn() },
    $transaction: jest.fn(async (callback: any) => callback(tx)),
  };
  const notifications = { create: jest.fn().mockResolvedValue({ id: 'n1' }) };
  const chat = { getOrderChat: jest.fn() };
  const orderEvents = new OrderEventsService(prisma as unknown as PrismaService);

  const crypto = { decrypt: jest.fn(), encrypt: jest.fn(), hash: jest.fn(), last4: jest.fn() };
  const service = new AdminService(
    prisma as unknown as PrismaService,
    notifications as unknown as NotificationsService,
    orderEvents,
    chat as any,
    crypto as any,
  );

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.$transaction.mockImplementation(async (callback: any) => callback(tx));
  });

  it('returns dashboard stats with totals, revenue and commission', async () => {
    prisma.user.count.mockResolvedValue(10);
    prisma.captainProfile.count.mockResolvedValueOnce(5).mockResolvedValueOnce(2);
    prisma.order.count.mockResolvedValueOnce(7).mockResolvedValueOnce(100);
    prisma.order.aggregate.mockResolvedValue({ _count: { id: 3 }, _sum: { price: 300, commission: 30 } });
    prisma.order.findMany.mockResolvedValue([]);

    const stats = await service.dashboard();

    expect(stats).toMatchObject({
      clients: 10, captains: 5, pendingCaptains: 2, openOrders: 7,
      totalOrders: 100, completedOrders: 3, revenue: 300, commission: 30,
    });
  });

  it('lists orders with status/date/captain/client filters', async () => {
    prisma.order.findMany.mockResolvedValue([]);

    await service.orders({ status: 'DELIVERED', from: '2026-01-01', to: '2026-12-31', captainId: 'cap1', clientId: 'c1' });

    expect(prisma.order.findMany).toHaveBeenCalledWith({
      where: {
        status: 'DELIVERED',
        captainId: 'cap1',
        clientId: 'c1',
        createdAt: { gte: new Date('2026-01-01'), lte: new Date('2026-12-31') },
      },
      take: 100, skip: 0,
      orderBy: { createdAt: 'desc' },
      include: expect.anything(),
    });
  });

  it('lists captains filtered by status', async () => {
    prisma.captainProfile.findMany.mockResolvedValue([]);

    await service.captains({ status: 'PENDING' });

    expect(prisma.captainProfile.findMany).toHaveBeenCalledWith({
      where: { status: 'PENDING' },
      orderBy: { createdAt: 'desc' },
      include: expect.anything(),
    });
  });

  it('lists wallet transactions with filters', async () => {
    prisma.walletTransaction.findMany.mockResolvedValue([]);

    await service.transactions({ type: 'COMMISSION_REFUND', take: 50 });

    expect(prisma.walletTransaction.findMany).toHaveBeenCalledWith({
      where: { type: 'COMMISSION_REFUND' },
      take: 50, skip: 0,
      orderBy: { createdAt: 'desc' },
      include: expect.anything(),
    });
  });

  const assignedOrder = {
    id: 'o1', reference: 'WS-1', clientId: 'c1', captainId: 'capA',
    status: 'ACCEPTED', commission: 20, deliveredAt: null, completedAt: null,
  };

  it('reassigns a captain: debits the new holder, refunds the previous one', async () => {
    tx.order.findUnique.mockResolvedValue({ ...assignedOrder });
    tx.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    tx.wallet.updateMany.mockResolvedValue({ count: 1 });
    tx.order.update.mockImplementation(async ({ data }: any) => ({ ...assignedOrder, ...data }));

    await service.updateOrder('o1', { captainId: 'capB' });

    expect(tx.wallet.updateMany).toHaveBeenCalled();
    const creations = tx.walletTransaction.create.mock.calls.map((call) => call[0].data);
    expect(creations).toHaveLength(2);
    expect(creations).toContainEqual(expect.objectContaining({ userId: 'capB', type: 'ORDER_COMMISSION' }));
    expect(creations).toContainEqual(expect.objectContaining({ userId: 'capA', type: 'COMMISSION_REFUND' }));
    expect(tx.order.update).toHaveBeenCalledWith({
      where: { id: 'o1' },
      data: expect.objectContaining({ captain: { connect: { id: 'capB' } }, status: 'ACCEPTED' }),
    });
  });

  it('refunds exactly once when reassigning and cancelling in one call', async () => {
    tx.order.findUnique.mockResolvedValue({ ...assignedOrder });
    tx.order.update.mockImplementation(async ({ data }: any) => ({ ...assignedOrder, ...data }));

    await service.updateOrder('o1', { captainId: 'capB', status: 'CANCELLED' });

    // New captain must not be debited for a cancelled order.
    expect(tx.wallet.updateMany).not.toHaveBeenCalled();
    const creations = tx.walletTransaction.create.mock.calls.map((call) => call[0].data);
    expect(creations).toHaveLength(1);
    expect(creations[0]).toMatchObject({ userId: 'capA', type: 'COMMISSION_REFUND' });
    expect(tx.order.update).toHaveBeenCalledWith({
      where: { id: 'o1' },
      data: expect.objectContaining({ status: 'CANCELLED' }),
    });
  });

  it('cancels an assigned order with a refund to the holder', async () => {
    tx.order.findUnique.mockResolvedValue({ ...assignedOrder });
    tx.order.update.mockImplementation(async ({ data }: any) => ({ ...assignedOrder, ...data }));

    await service.updateOrder('o1', { status: 'CANCELLED' });

    expect(tx.wallet.update).toHaveBeenCalledWith({
      where: { userId: 'capA' },
      data: { balance: { increment: expect.anything() } },
    });
    expect(tx.walletTransaction.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ userId: 'capA', type: 'COMMISSION_REFUND' }),
    });
  });

  it('returns unassigned orders to SEARCHING_CAPTAIN with a refund', async () => {
    tx.order.findUnique.mockResolvedValue({ ...assignedOrder });
    tx.order.update.mockImplementation(async ({ data }: any) => ({ ...assignedOrder, ...data }));

    await service.updateOrder('o1', { captainId: '' });

    expect(tx.wallet.updateMany).not.toHaveBeenCalled();
    expect(tx.walletTransaction.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ userId: 'capA', type: 'COMMISSION_REFUND' }),
    });
    expect(tx.order.update).toHaveBeenCalledWith({
      where: { id: 'o1' },
      data: expect.objectContaining({ captain: { disconnect: true }, status: 'SEARCHING_CAPTAIN' }),
    });
  });

  it('rejects invalid order statuses', async () => {
    tx.order.findUnique.mockResolvedValue({ ...assignedOrder });

    await expect(service.updateOrder('o1', { status: 'FLYING' })).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(tx.order.update).not.toHaveBeenCalled();
  });

  it('rejects cancelling a COMPLETED order', async () => {
    tx.order.findUnique.mockResolvedValue({ ...assignedOrder, status: 'COMPLETED' });

    await expect(service.updateOrder('o1', { status: 'CANCELLED' })).rejects.toBeInstanceOf(BadRequestException);
    expect(tx.order.update).not.toHaveBeenCalled();
    expect(tx.wallet.update).not.toHaveBeenCalled();
    expect(tx.walletTransaction.create).not.toHaveBeenCalled();
  });

  it('rejects modifying a CANCELLED order', async () => {
    tx.order.findUnique.mockResolvedValue({ ...assignedOrder, status: 'CANCELLED', captainId: null });

    await expect(service.updateOrder('o1', { status: 'ACCEPTED' })).rejects.toBeInstanceOf(BadRequestException);
    expect(tx.order.update).not.toHaveBeenCalled();
  });

  it('rejects cancelling a DELIVERED order for now', async () => {
    tx.order.findUnique.mockResolvedValue({ ...assignedOrder, status: 'DELIVERED' });

    await expect(service.updateOrder('o1', { status: 'CANCELLED' })).rejects.toBeInstanceOf(BadRequestException);
    expect(tx.order.update).not.toHaveBeenCalled();
    expect(tx.walletTransaction.create).not.toHaveBeenCalled();
  });

  it('still allows status-only override on non-terminal orders', async () => {
    tx.order.findUnique.mockResolvedValue({ ...assignedOrder });
    tx.order.update.mockImplementation(async ({ data }: any) => ({ ...assignedOrder, ...data }));

    await service.updateOrder('o1', { status: 'PICKED_UP' });

    expect(tx.order.update).toHaveBeenCalledWith({
      where: { id: 'o1' },
      data: expect.objectContaining({ status: 'PICKED_UP' }),
    });
    expect(tx.walletTransaction.create).not.toHaveBeenCalled();
  });

  it('notifies the captain on suspend and restore with distinct messages', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({ userId: 'cap1', status: 'ACTIVE' });
    prisma.captainProfile.update.mockResolvedValue({ userId: 'cap1', status: 'SUSPENDED' });

    await service.reviewCaptain('cap1', 'SUSPENDED' as any);
    expect(notifications.create).toHaveBeenCalledWith('cap1', 'Account suspended', expect.any(String), 'CAPTAIN', {
      screen: 'CAPTAIN_REVIEW',
      status: 'SUSPENDED',
    });

    prisma.captainProfile.findUnique.mockResolvedValue({ userId: 'cap1', status: 'SUSPENDED' });
    prisma.captainProfile.update.mockResolvedValue({ userId: 'cap1', status: 'ACTIVE' });

    await service.reviewCaptain('cap1', 'ACTIVE' as any);
    expect(notifications.create).toHaveBeenCalledWith('cap1', 'Account restored', expect.any(String), 'CAPTAIN', {
      screen: 'CAPTAIN_REVIEW',
      status: 'ACTIVE',
    });
  });

    it('suspends and restores client accounts', async () => {

    prisma.user.update.mockResolvedValue({ id: 'c1', name: 'Client', suspendedAt: new Date() });

    await service.suspendUser('c1', true);
    expect(prisma.user.update).toHaveBeenCalledWith({
      where: { id: 'c1' },
      data: { suspendedAt: expect.any(Date) },
      select: expect.anything(),
    });

    await service.suspendUser('c1', false);
    expect(prisma.user.update).toHaveBeenCalledWith({
      where: { id: 'c1' },
      data: { suspendedAt: null },
      select: expect.anything(),
    });
  });

  it('records admin overrides with the admin actor', async () => {
    tx.order.findUnique.mockResolvedValue({ ...assignedOrder });
    tx.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    tx.wallet.updateMany.mockResolvedValue({ count: 1 });
    tx.order.update.mockImplementation(async ({ data }: any) => ({ ...assignedOrder, ...data }));

    await service.updateOrder('o1', { captainId: 'capB' }, 'admin1');

    expect(tx.orderEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        orderId: 'o1', fromStatus: 'ACCEPTED', toStatus: 'ACCEPTED',
        actorId: 'admin1', actorRole: 'ADMIN',
      }),
    });
  });

  it('records admin reassignment and status override events', async () => {
    tx.order.findUnique.mockResolvedValue({ ...assignedOrder, captainId: null, status: 'SEARCHING_CAPTAIN' });
    tx.order.update.mockImplementation(async ({ data }: any) => ({ ...assignedOrder, ...data }));

    await service.updateOrder('o1', { status: 'CANCELLED' }, 'admin1');

    expect(tx.orderEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        orderId: 'o1', fromStatus: 'SEARCHING_CAPTAIN', toStatus: 'CANCELLED',
        actorId: 'admin1', actorRole: 'ADMIN',
      }),
    });
  });

  it('returns the order timeline with actor names', async () => {
    prisma.order.findUnique.mockResolvedValue({ id: 'o1' });
    prisma.orderEvent.findMany.mockResolvedValue([
      { id: 'e1', orderId: 'o1', fromStatus: null, toStatus: 'SEARCHING_CAPTAIN', actorId: 'c1', actorRole: 'CLIENT', note: 'Order created', createdAt: new Date() },
      { id: 'e2', orderId: 'o1', fromStatus: 'SEARCHING_CAPTAIN', toStatus: 'ACCEPTED', actorId: 'capA', actorRole: 'CAPTAIN', note: 'Captain accepted the order', createdAt: new Date() },
    ]);
    prisma.user.findMany.mockResolvedValue([
      { id: 'c1', name: 'Client One' },
      { id: 'capA', name: 'Captain A' },
    ]);

    const events = await service.getOrderEvents('o1');

    expect(events).toHaveLength(2);
    expect(events[0]).toMatchObject({ actorId: 'c1', actorName: 'Client One' });
    expect(events[1]).toMatchObject({ actorId: 'capA', actorName: 'Captain A' });
  });

  it('returns order proofs with captain names and no internal paths', async () => {
    prisma.order.findUnique.mockResolvedValue({ id: 'o1' });
    prisma.orderProof.findMany.mockResolvedValue([
      { id: 'p1', orderId: 'o1', type: 'PICKUP', note: null, capturedById: 'capA', photoPath: 'proofs/o1/x.jpg', createdAt: new Date() },
    ]);
    prisma.user.findMany.mockResolvedValue([{ id: 'capA', name: 'Captain A' }]);

    const proofs = await service.orderProofs('o1');

    expect(proofs).toHaveLength(1);
    expect(proofs[0]).not.toHaveProperty('photoPath');
    expect(proofs[0]).toMatchObject({ type: 'PICKUP', capturedByName: 'Captain A', hasPhoto: true });
  });

  it('filters acknowledgement records and caps pagination at 100', async () => {
    prisma.policyAcknowledgement.findMany.mockResolvedValue([]);

    await service.acknowledgements({
      userId: 'u1', orderId: 'o1', type: 'SENSITIVE_CATEGORY',
      from: '2026-01-01T00:00:00.000Z', to: '2026-01-31T00:00:00.000Z', take: 500, skip: 20,
    });

    expect(prisma.policyAcknowledgement.findMany).toHaveBeenCalledWith({
      where: {
        userId: 'u1', orderId: 'o1', type: 'SENSITIVE_CATEGORY',
        createdAt: { gte: new Date('2026-01-01T00:00:00.000Z'), lte: new Date('2026-01-31T00:00:00.000Z') },
      },
      take: 100, skip: 20, orderBy: { createdAt: 'desc' }, include: expect.anything(),
    });
  });

  it('returns invoice details without its private photo path', async () => {
    prisma.purchaseInvoice.findUnique.mockResolvedValue({
      id: 'invoice1', orderId: 'o1', amount: 120, photoPath: 'proofs/o1/private.png', status: 'SUBMITTED',
    });

    const invoice = await service.orderInvoice('o1');

    expect(invoice).toMatchObject({ id: 'invoice1', hasPhoto: true });
    expect(invoice).not.toHaveProperty('photoPath');
  });

  describe('document and photo serving', () => {
    it('serves a captain document stored with Windows separators', async () => {
      prisma.captainProfile.findUnique.mockResolvedValue({ nationalIdDocument: 'captains\\u1\\a.jpg' });
      jest.spyOn(fs, 'existsSync').mockReturnValue(true);

      const file = await service.captainDocument('u1', 'identity');

      expect(file.path.endsWith('a.jpg')).toBe(true);
      expect(file.mimeType).toBe('image/jpeg');
    });

    it('rejects another captain document path', async () => {
      prisma.captainProfile.findUnique.mockResolvedValue({ nationalIdDocument: 'captains\\someone-else\\a.jpg' });

      await expect(service.captainDocument('u1', 'identity')).rejects.toBeInstanceOf(NotFoundException);
    });

    it('rejects un-uploaded captain documents', async () => {
      prisma.captainProfile.findUnique.mockResolvedValue({ nationalIdDocument: 'PENDING_UPLOAD' });

      await expect(service.captainDocument('u1', 'identity')).rejects.toBeInstanceOf(NotFoundException);
    });

    it('serves invoice photos stored with Windows separators', async () => {
      prisma.purchaseInvoice.findUnique.mockResolvedValue({ photoPath: 'proofs\\o1\\inv.png' });
      jest.spyOn(fs, 'existsSync').mockReturnValue(true);

      const file = await service.orderInvoicePhoto('o1');

      expect(file.mimeType).toBe('image/png');
    });
  });
});
