import { BadRequestException, ForbiddenException, Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import { CaptainStatus, EventActor, NotificationType, OrderStatus, PolicyAcknowledgementType, Prisma, TopUpStatus, UserRole, WalletTransactionType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { OrderEventsService } from '../order-events/order-events.service';
import { ChatService } from '../firebase/chat.service';
import { existsSync } from 'fs';
import { resolve } from 'path';
import { AdminOrderDto } from './dto/admin-order.dto';
import { AdminCaptainsQueryDto } from './dto/admin-captains-query.dto';
import { AdminOrdersQueryDto } from './dto/admin-orders-query.dto';
import { AdminTransactionsQueryDto } from './dto/admin-transactions-query.dto';
import { UpdatePricingDto } from './dto/update-pricing.dto';
import { AdminTopUpsQueryDto } from '../topups/dto/admin-topups-query.dto';
import { AdminAcknowledgementsQueryDto } from './dto/admin-acknowledgements-query.dto';
import { resolveUploadPath, toPosixPath } from '../orders/proof-upload';
import { NationalIdCryptoService } from '../captains/national-id-crypto.service';

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly orderEvents: OrderEventsService,
    private readonly chat: ChatService,
    private readonly crypto: NationalIdCryptoService,
  ) {}

  async dashboard() {
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 6);
    sevenDaysAgo.setHours(0, 0, 0, 0);

    const [clients, captains, pendingCaptains, openOrders, totalOrders, completed, recentOrders, pastCompletedOrders] = await Promise.all([
      this.prisma.user.count({ where: { role: UserRole.CLIENT } }),
      this.prisma.captainProfile.count({ where: { status: CaptainStatus.ACTIVE } }),
      this.prisma.captainProfile.count({ where: { status: CaptainStatus.PENDING } }),
      this.prisma.order.count({ where: { status: { in: [OrderStatus.PENDING, OrderStatus.SEARCHING_CAPTAIN, OrderStatus.ACCEPTED, OrderStatus.ARRIVED_AT_PICKUP, OrderStatus.PICKED_UP, OrderStatus.ON_THE_WAY] } } }),
      this.prisma.order.count(),
      this.prisma.order.aggregate({ where: { status: OrderStatus.COMPLETED }, _count: { id: true }, _sum: { price: true, commission: true } }),
      this.prisma.order.findMany({ take: 8, orderBy: { createdAt: 'desc' }, include: { client: { select: { name: true } }, captain: { select: { name: true } } } }),
      this.prisma.order.findMany({
        where: {
          status: OrderStatus.COMPLETED,
          createdAt: { gte: sevenDaysAgo },
        },
        select: { createdAt: true, price: true, commission: true },
      }),
    ]);

    const dayMap = new Map<string, { date: string; day: string; revenue: number; commission: number; orders: number }>();
    for (let i = 6; i >= 0; i--) {
      const d = new Date();
      d.setDate(d.getDate() - i);
      const iso = d.toISOString().slice(0, 10);
      const dayName = d.toLocaleDateString('en-US', { weekday: 'short' });
      dayMap.set(iso, { date: iso, day: dayName, revenue: 0, commission: 0, orders: 0 });
    }

    if (Array.isArray(pastCompletedOrders)) {
      for (const order of pastCompletedOrders) {
        const iso = order.createdAt ? new Date(order.createdAt).toISOString().slice(0, 10) : '';
        const entry = dayMap.get(iso);
        if (entry) {
          entry.revenue += Number(order.price ?? 0);
          entry.commission += Number(order.commission ?? 0);
          entry.orders += 1;
        }
      }
    }

    return {
      clients, captains, pendingCaptains, openOrders, totalOrders,
      completedOrders: completed._count.id,
      revenue: Number(completed._sum.price ?? 0),
      commission: Number(completed._sum.commission ?? 0),
      recentOrders,
      weeklyRevenue: Array.from(dayMap.values()),
    };
  }

  orders(query: AdminOrdersQueryDto) {
    const where: Prisma.OrderWhereInput = {};
    if (query.status) where.status = query.status as OrderStatus;
    if (query.captainId) where.captainId = query.captainId;
    if (query.clientId) where.clientId = query.clientId;
    if (query.from || query.to) {
      where.createdAt = {
        ...(query.from ? { gte: new Date(query.from) } : {}),
        ...(query.to ? { lte: new Date(query.to) } : {}),
      };
    }
    return this.prisma.order.findMany({
      where, take: query.take ?? 100, skip: query.skip ?? 0,
      orderBy: { createdAt: 'desc' },
      include: {
        client: { select: { id: true, name: true, email: true, phone: true } },
        captain: { select: { id: true, name: true, phone: true } },
      },
    });
  }

  async captains(query: AdminCaptainsQueryDto) {
    const items = await this.prisma.captainProfile.findMany({
      where: query.status ? { status: query.status as CaptainStatus } : {},
      orderBy: { createdAt: 'desc' },
      include: {
        user: { select: { id: true, name: true, email: true, phone: true, wallet: true } },
      },
    });
    return items.map((c) => {
      const rest = c as any;
      delete rest.nationalIdEncrypted;
      delete rest.nationalIdHash;
      return rest;
    });
  }

  async captain(userId: string) {
    const profile = await this.prisma.captainProfile.findUnique({
      where: { userId },
      include: {
        user: { select: { id: true, name: true, email: true, phone: true, wallet: true } },
      },
    });
    if (!profile) throw new NotFoundException('Captain application not found');
    const rest = profile as any;
    delete rest.nationalIdEncrypted;
    delete rest.nationalIdHash;
    return rest;
  }

  transactions(query: AdminTransactionsQueryDto) {
    const where: Prisma.WalletTransactionWhereInput = {};
    if (query.type) where.type = query.type as WalletTransactionType;
    if (query.userId) where.userId = query.userId;
    if (query.orderId) where.orderId = query.orderId;
    return this.prisma.walletTransaction.findMany({
      where, take: query.take ?? 100, skip: query.skip ?? 0,
      orderBy: { createdAt: 'desc' },
      include: {
        user: { select: { id: true, name: true, email: true } },
        order: { select: { id: true, reference: true } },
      },
    });
  }

  topUps(query: AdminTopUpsQueryDto) {
    const where: Prisma.TopUpWhereInput = {};
    if (query.status) where.status = query.status as TopUpStatus;
    if (query.userId) where.userId = query.userId;
    return this.prisma.topUp.findMany({
      where, take: query.take ?? 100, skip: query.skip ?? 0,
      orderBy: { createdAt: 'desc' },
      include: { user: { select: { id: true, name: true, email: true } } },
    });
  }

  /**
   * Full order timeline for admins, enriched with the actor's name.
   */
  async getOrderEvents(orderId: string) {
    const order = await this.prisma.order.findUnique({ where: { id: orderId }, select: { id: true } });
    if (!order) throw new NotFoundException('Order not found');
    const events = await this.orderEvents.list(orderId);
    const actorIds = [...new Set(events.map((event) => event.actorId).filter((id): id is string => !!id))];
    const actors = actorIds.length
      ? await this.prisma.user.findMany({ where: { id: { in: actorIds } }, select: { id: true, name: true } })
      : [];
    const names = new Map(actors.map((actor) => [actor.id, actor.name]));
    return events.map((event) => ({ ...event, actorName: event.actorId ? names.get(event.actorId) ?? null : null }));
  }

  /**
   * Proofs for admins. Internal file paths stay hidden; photos stream through
   * the ownership-checked user photo endpoint, which also allows ADMIN.
   */
  async orderProofs(orderId: string) {
    const order = await this.prisma.order.findUnique({ where: { id: orderId }, select: { id: true } });
    if (!order) throw new NotFoundException('Order not found');
    const proofs = await this.prisma.orderProof.findMany({ where: { orderId }, orderBy: { createdAt: 'asc' } });
    const ids = [...new Set(proofs.map((proof) => proof.capturedById))];
    const users = ids.length
      ? await this.prisma.user.findMany({ where: { id: { in: ids } }, select: { id: true, name: true } })
      : [];
    const names = new Map(users.map((user) => [user.id, user.name]));
    return proofs.map(({ photoPath: _photoPath, ...proof }) => ({
      ...proof,
      capturedByName: names.get(proof.capturedById) ?? null,
      hasPhoto: !!_photoPath,
    }));
  }

  acknowledgements(query: AdminAcknowledgementsQueryDto) {
    const where: Prisma.PolicyAcknowledgementWhereInput = {};
    if (query.userId) where.userId = query.userId;
    if (query.orderId) where.orderId = query.orderId;
    if (query.type) where.type = query.type as PolicyAcknowledgementType;
    if (query.from || query.to) {
      where.createdAt = {
        ...(query.from ? { gte: new Date(query.from) } : {}),
        ...(query.to ? { lte: new Date(query.to) } : {}),
      };
    }
    return this.prisma.policyAcknowledgement.findMany({
      where,
      take: Math.min(query.take ?? 100, 100),
      skip: query.skip ?? 0,
      orderBy: { createdAt: 'desc' },
      include: {
        user: { select: { id: true, name: true, role: true } },
        order: { select: { id: true, reference: true, category: true } },
      },
    });
  }

  async orderInvoice(orderId: string) {
    const invoice = await this.prisma.purchaseInvoice.findUnique({ where: { orderId } });
    if (!invoice) throw new NotFoundException('Invoice not found');
    const { photoPath, ...visible } = invoice;
    return { ...visible, hasPhoto: !!photoPath };
  }

  async orderInvoicePhoto(orderId: string) {
    const invoice = await this.prisma.purchaseInvoice.findUnique({ where: { orderId }, select: { photoPath: true } });
    const photoPath = invoice?.photoPath ? toPosixPath(invoice.photoPath) : '';
    if (!photoPath.startsWith('proofs/')) throw new NotFoundException('Invoice photo not found');
    const resolved = resolveUploadPath(photoPath);
    if (!resolved || !existsSync(resolved.path)) throw new NotFoundException('Invoice photo is missing');
    const mimeType = photoPath.endsWith('.png') ? 'image/png' : photoPath.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
    return { path: resolved.path, mimeType };
  }

  async captainDocument(userId: string, type: string) {
    const fields = {
      identity: 'nationalIdDocument',
      'identity-back': 'nationalIdBackDocument',
      license: 'licenseDocument',
      'license-back': 'licenseBackDocument',
      vehicle: 'vehicleDocument',
      'vehicle-back': 'vehicleBackDocument',
      'profile-photo': 'profilePhotoDocument',
    } as const;
    const field = fields[type as keyof typeof fields];
    if (!field) throw new NotFoundException('Document not found');
    const profile = await this.prisma.captainProfile.findUnique({ where: { userId } });
    const storedPath = profile?.[field] ? toPosixPath(profile[field]) : undefined;
    if (!storedPath || storedPath === 'PENDING_UPLOAD' || !storedPath.startsWith(`captains/${userId}/`)) {
      throw new NotFoundException('Document has not been uploaded');
    }
    const root = resolve(process.cwd(), 'uploads');
    const path = resolve(root, storedPath);
    if (!path.startsWith(`${root}/`) && !path.startsWith(`${root}\\`)) {
      throw new NotFoundException('Document not found');
    }
    if (!existsSync(path)) throw new NotFoundException('Document file is missing');
    const mimeType = path.endsWith('.pdf') ? 'application/pdf' : path.endsWith('.png') ? 'image/png' : 'image/jpeg';
    return { path, mimeType };
  }

  clients() {
    return this.prisma.user.findMany({ where: { role: UserRole.CLIENT }, select: {
      id: true, name: true, email: true, phone: true, suspendedAt: true, createdAt: true,
      _count: { select: { clientOrders: true } },
    }, orderBy: { createdAt: 'desc' }, take: 200 });
  }

  wallets() {
    return this.prisma.user.findMany({
      where: { role: UserRole.CAPTAIN },
      select: {
        id: true, name: true, email: true, wallet: true,
        walletTransactions: { orderBy: { createdAt: 'desc' }, take: 20 },
      },
      orderBy: { name: 'asc' }, take: 200,
    });
  }

  pricing() {
    return this.prisma.pricingSettings.upsert({ where: { id: 'default' }, update: {}, create: {} });
  }

  savePricing(input: UpdatePricingDto) {
    return this.prisma.pricingSettings.upsert({ where: { id: 'default' }, create: input, update: input });
  }

  async reviewCaptain(userId: string, status: CaptainStatus, reason?: string) {
    const current = await this.prisma.captainProfile.findUnique({ where: { userId } });
    if (!current) throw new NotFoundException('Captain application not found');

    const approval = status === CaptainStatus.ACTIVE && current.status !== CaptainStatus.SUSPENDED;
    if (approval) {
      const docFields = [
        'nationalIdDocument', 'nationalIdBackDocument', 'licenseDocument',
        'licenseBackDocument', 'vehicleDocument', 'vehicleBackDocument', 'profilePhotoDocument',
      ] as const;
      const missing = docFields.filter((field) => !current[field] || current[field] === 'PENDING_UPLOAD');
      if (missing.length) {
        throw new UnprocessableEntityException(
          `Cannot approve: ${missing.length} required document(s) have not been uploaded`,
        );
      }
    }

    const rejection = status === CaptainStatus.REJECTED;
    const trimmedReason = (reason ?? '').trim();
    if (rejection && trimmedReason.length < 3) {
      throw new BadRequestException('A rejection reason is required');
    }

    const captain = await this.prisma.captainProfile.update({
      where: { userId },
      data: {
        status,
        reviewedAt: new Date(),
        ...(approval ? { approvedAt: new Date(), rejectionReason: null } : {}),
        ...(rejection ? { rejectionReason: trimmedReason } : {}),
      },
    });
    try {
      const messages: Partial<Record<CaptainStatus, [string, string]>> = {
        [CaptainStatus.ACTIVE]: current.status === CaptainStatus.SUSPENDED
          ? ['Account restored', 'Your captain account was restored. You can accept deliveries again.']
          : ['Account approved', 'Your captain account was approved. You can now accept deliveries.'],
        [CaptainStatus.REJECTED]: ['Application update', trimmedReason
          ? `Your captain application was rejected: ${trimmedReason}. You can update your documents and resubmit.`
          : 'Your captain application needs attention. Please contact support.'],
        [CaptainStatus.SUSPENDED]: ['Account suspended', 'Your captain account was suspended. Please contact support.'],
      };
      const message = messages[status];
      if (message) {
        await this.notifications.create(userId, message[0], message[1], NotificationType.CAPTAIN, {
          screen: 'CAPTAIN_REVIEW',
          status,
        });
      }
    } catch {
      // Notifications are non-critical.
    }
    return captain;
  }

  async suspendUser(userId: string, suspended: boolean) {
    const user = await this.prisma.user.update({ where: { id: userId }, data: { suspendedAt: suspended ? new Date() : null }, select: { id: true, name: true, suspendedAt: true } }).catch(() => null);
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  /**
   * Get chat data for an order (meta + messages) - Admin only
   */
  async getOrderChat(orderId: string) {
    const order = await this.prisma.order.findUnique({ where: { id: orderId }, select: { id: true } });
    if (!order) throw new NotFoundException('Order not found');

    const [meta, messages] = await Promise.all([
      this.chat.getChatMeta(orderId),
      this.chat.getChatMessages(orderId, 500),
    ]);

    return { meta, messages };
  }

  /**
   * Admin override: reassign captain and/or force any status.
   * Money rules (all inside one transaction, refund happens at most once):
   * - New assignee (unless cancelling): must be ACTIVE + cover commission -> reserve.
   * - Previous holder loses the order, or order is cancelled while assigned
   *   -> exactly one COMMISSION_REFUND to the previous holder.
   * - Unassign without explicit status returns the order to SEARCHING_CAPTAIN.
   */
  updateOrder(orderId: string, input: AdminOrderDto, adminId?: string) {
    return this.prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw new NotFoundException('Order not found');

      // Terminal-state guard: COMPLETED and CANCELLED orders are immutable,
      // even for admins. Reopening them would corrupt wallet history.
      // NOTE: `.includes()` on a typed array is used (instead of `===`)
      // so TypeScript does not narrow `currentStatus` for the code below.
      const TERMINAL_STATUSES: OrderStatus[] = [OrderStatus.COMPLETED, OrderStatus.CANCELLED];
      const currentStatus: OrderStatus = order.status;
      if (TERMINAL_STATUSES.includes(currentStatus)) {
        throw new BadRequestException(`Order is already ${currentStatus.toLowerCase()} and cannot be modified`);
      }

      let nextStatus: OrderStatus = currentStatus;
      if (input.status !== undefined) {
        if (!Object.values(OrderStatus).includes(input.status as OrderStatus)) {
          throw new UnprocessableEntityException('Invalid order status');
        }
        nextStatus = input.status as OrderStatus;
      }

      const captainChanged = input.captainId !== undefined && (input.captainId || null) !== order.captainId;
      const newCaptainId = input.captainId !== undefined ? input.captainId || null : order.captainId;
      const cancelling = nextStatus === OrderStatus.CANCELLED && currentStatus !== OrderStatus.CANCELLED;
      const previousHolder = order.captainId;

      // Product policy (deliberately unchanged behavior): cancelling a DELIVERED
      // order stays rejected. The delivery commission is already earned at that
      // point, and refunding it still needs an explicit product decision
      // (partial refund? penalty? approval flow?). See OrderEvent history for audit.
      if (cancelling && order.status === OrderStatus.DELIVERED) {
        throw new BadRequestException('Delivered orders cannot be cancelled yet. Please contact support.');
      }

      if (captainChanged && newCaptainId && !cancelling) {
        const captain = await tx.captainProfile.findUnique({ where: { userId: newCaptainId } });
        if (!captain || captain.status !== CaptainStatus.ACTIVE) throw new ForbiddenException('Captain is not approved');
        const debit = await tx.wallet.updateMany({ where: { userId: newCaptainId, balance: { gte: order.commission } }, data: { balance: { decrement: order.commission } } });
        if (!debit.count) throw new UnprocessableEntityException('Captain wallet cannot cover the commission');
        await tx.walletTransaction.create({ data: { userId: newCaptainId, orderId, type: WalletTransactionType.ORDER_COMMISSION, amount: new Prisma.Decimal(order.commission).negated(), note: 'Commission reserved on admin reassignment' } });
      }

      if (previousHolder && (newCaptainId !== previousHolder || cancelling)) {
        await tx.wallet.update({ where: { userId: previousHolder }, data: { balance: { increment: order.commission } } });
        await tx.walletTransaction.create({ data: { userId: previousHolder, orderId, type: WalletTransactionType.COMMISSION_REFUND, amount: order.commission, note: cancelling ? 'Commission refunded on admin cancellation' : 'Commission released on admin reassignment' } });
      }

      const data: Prisma.OrderUpdateInput = {};
      if (captainChanged) {
        data.captain = newCaptainId ? { connect: { id: newCaptainId } } : { disconnect: true };
        if (input.status === undefined) {
          nextStatus = newCaptainId ? OrderStatus.ACCEPTED : OrderStatus.SEARCHING_CAPTAIN;
        }
        if (newCaptainId && !previousHolder) data.acceptedAt = new Date();
      }
      data.status = nextStatus;
      if (nextStatus === OrderStatus.DELIVERED && !order.deliveredAt) data.deliveredAt = new Date();
      if (nextStatus === OrderStatus.COMPLETED && !order.completedAt) data.completedAt = new Date();

      const updated = await tx.order.update({ where: { id: orderId }, data });

      if (nextStatus !== order.status || captainChanged) {
        const notes: string[] = [];
        if (captainChanged) {
          notes.push(newCaptainId ? 'Captain reassigned by admin' : 'Captain unassigned by admin');
        }
        if (nextStatus !== order.status) notes.push('Status overridden by admin');
        await this.orderEvents.record(tx, {
          orderId,
          fromStatus: order.status,
          toStatus: nextStatus,
          actorId: adminId ?? null,
          actorRole: EventActor.ADMIN,
          note: notes.join('; '),
        });
      }

      try {
        if (captainChanged || (input.status !== undefined && nextStatus !== currentStatus)) {
          await this.notifications.create(
            order.clientId,
            'تحديث من الدعم',
            `تم تحديث الطلب ${order.reference}: ${arabicAdminStatus(nextStatus)}${newCaptainId ? ' (تم تعيين مندوب)' : ''}.`,
            NotificationType.ORDER,
            { orderId },
          );
        }
      } catch {
        // Notifications are non-critical.
      }
      return updated;
    });
  }
}
function arabicAdminStatus(status: OrderStatus) {
  switch (status) {
    case OrderStatus.PENDING: return 'قيد الانتظار';
    case OrderStatus.SEARCHING_CAPTAIN: return 'جارٍ البحث عن مندوب';
    case OrderStatus.ACCEPTED: return 'تم قبول الطلب';
    case OrderStatus.ARRIVED_AT_PICKUP: return 'وصل المندوب إلى موقع الاستلام';
    case OrderStatus.PICKED_UP: return 'تم استلام الشحنة';
    case OrderStatus.ON_THE_WAY: return 'الشحنة في الطريق';
    case OrderStatus.DELIVERED: return 'تم التسليم';
    case OrderStatus.COMPLETED: return 'اكتمل الطلب';
    case OrderStatus.CANCELLED: return 'ملغي';
    default: return status;
  }
}
