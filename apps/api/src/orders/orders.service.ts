import { BadRequestException, ConflictException, ForbiddenException, Injectable, Logger, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import { CaptainStatus, EventActor, NotificationType, OrderStatus, PolicyAcknowledgementType, Prisma, ProofType, PurchaseInvoiceStatus, ShipmentCategory, UserRole, WalletTransactionType } from '@prisma/client';
import { existsSync } from 'fs';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.module';
import { NotificationsService } from '../notifications/notifications.service';
import { OrderEventsService } from '../order-events/order-events.service';
import { PoliciesService } from '../policies/policies.service';
import { POLICY_VERSION } from '../policies/policy-content.v1';
import { ChatService } from '../firebase/chat.service';
import { FcmService } from '../firebase/fcm.service';
import { CreateOrderDto } from './dto/create-order.dto';
import { SubmitInvoiceDto } from './dto/submit-invoice.dto';
import { RespondInvoiceDto } from './dto/respond-invoice.dto';
import { QuoteOrderDto } from './dto/quote-order.dto';
import { RateOrderDto } from './dto/rate-order.dto';
import { DEFAULT_MAX_RADIUS_KM, DEFAULT_MIN_RADIUS_KM, ORDER_SEARCH_EXPIRY_MINUTES } from './orders.constants';
import { ProofPhotoInput, resolveUploadPath, saveProofPhoto, toPosixPath } from './proof-upload';

const radians = (degrees: number) => degrees * Math.PI / 180;

export function distanceKm(fromLat: number, fromLon: number, toLat: number, toLon: number) {
  const deltaLat = radians(toLat - fromLat);
  const deltaLon = radians(toLon - fromLon);
  const arc = Math.sin(deltaLat / 2) ** 2 + Math.cos(radians(fromLat)) * Math.cos(radians(toLat)) * Math.sin(deltaLon / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(arc), Math.sqrt(1 - arc));
}

const round2 = (value: number) => Math.round(value * 100) / 100;

const ratingLogger = new Logger('OrderRating');

/** Statuses where a captain is on the way and must keep sending location. */
export const ACTIVE_TRIP_STATUSES: OrderStatus[] = [
  OrderStatus.ACCEPTED,
  OrderStatus.ARRIVED_AT_PICKUP,
  OrderStatus.PICKED_UP,
  OrderStatus.ON_THE_WAY,
];

@Injectable()
export class OrdersService {
  private readonly logger = new Logger(OrdersService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly notifications: NotificationsService,
    private readonly orderEvents: OrderEventsService,
    private readonly policies: PoliciesService,
    private readonly chat: ChatService,
    private readonly fcm: FcmService,
  ) {}

  /** Best-effort notification: never breaks the order flow. */
  private async notify(
    userId: string,
    title: string,
    body: string,
    type: NotificationType = NotificationType.ORDER,
    metadata?: Prisma.InputJsonValue,
  ) {
    try {
      await this.notifications.create(userId, title, body, type, metadata);
    } catch {
      // Notifications are non-critical; order state is authoritative in PostgreSQL.
    }
  }

  private notifyClient(order: { clientId: string; reference: string; id: string }, title: string, body: string) {
    return this.notify(order.clientId, title, body, NotificationType.ORDER, { orderId: order.id });
  }

  /**
   * Returns a previously reserved commission to the captain's wallet.
   * Must be called inside a transaction after the order row was updated.
   */
  private refundCommission(
    tx: Prisma.TransactionClient,
    captainId: string,
    order: { id: string; commission: unknown },
    note: string,
  ) {
    const amount = new Prisma.Decimal(order.commission as number);
    return (async () => {
      await tx.wallet.update({ where: { userId: captainId }, data: { balance: { increment: amount } } });
      await tx.walletTransaction.create({
        data: { userId: captainId, orderId: order.id, type: WalletTransactionType.COMMISSION_REFUND, amount, note },
      });
    })();
  }

  async quote(input: QuoteOrderDto) {
    const [pricing, distance] = await Promise.all([
      this.prisma.pricingSettings.upsert({ where: { id: 'default' }, update: {}, create: {} }),
      Promise.resolve(distanceKm(input.pickupLatitude, input.pickupLongitude, input.deliveryLatitude, input.deliveryLongitude)),
    ]);
    const distanceRounded = Math.round(distance * 100) / 100;
    const price = Number(pricing.basePrice) + distanceRounded * Number(pricing.pricePerKm);
    const commission = price * Number(pricing.commissionPercent) / 100;
    return { currency: 'EGP', distanceKm: distanceRounded, price: Number(price.toFixed(2)), commission: Number(commission.toFixed(2)) };
  }

  async create(clientId: string, input: CreateOrderDto) {
    const client = await this.prisma.user.findUnique({ where: { id: clientId }, select: { phone: true } });
    if (!client?.phone?.trim()) {
      throw new ForbiddenException({ code: 'PROFILE_INCOMPLETE', missing: ['phone'] });
    }
    const settings = await this.prisma.pricingSettings.upsert({ where: { id: 'default' }, update: {}, create: {} });
    if (settings.disabledCategories?.includes(input.category)) {
      throw new BadRequestException({ code: 'CATEGORY_DISABLED', message: 'هذه الفئة متوقفة مؤقتًا عن استقبال الطلبات' });
    }
    const budgetCategories: ShipmentCategory[] = [ShipmentCategory.PURCHASES, ShipmentCategory.FOOD];
    if (input.estimatedBudget !== undefined && !budgetCategories.includes(input.category)) {
      throw new BadRequestException('Estimated budget is only available for purchases and food');
    }
    if (isSensitiveCategory(input.category) && !(await this.policies.hasAcknowledgement(
      clientId,
      PolicyAcknowledgementType.SENSITIVE_CATEGORY,
      { orderId: null, category: input.category },
    ))) {
      throw ackRequired(PolicyAcknowledgementType.SENSITIVE_CATEGORY, { category: input.category });
    }
    const quote = await this.quote(input);
    const order = await this.prisma.$transaction(async (tx) => {
      const created = await tx.order.create({
        data: {
          clientId, ...input, description: input.description?.trim() || '', status: OrderStatus.SEARCHING_CAPTAIN,
          distanceKm: quote.distanceKm, price: quote.price, commission: quote.commission,
        },
      });
      await this.orderEvents.record(tx, {
        orderId: created.id,
        fromStatus: null,
        toStatus: OrderStatus.SEARCHING_CAPTAIN,
        actorId: clientId,
        actorRole: EventActor.CLIENT,
        note: 'Order created',
      });
      return created;
    });
    // Both sides get an in-app record: the client sees the created order, and
    // captains see accepted/updated orders through their existing notifications.
    await this.notify(clientId, 'تم إنشاء الطلب', `تم استلام الطلب ${order.reference} وجارٍ البحث عن مندوب.`, NotificationType.ORDER, {
      orderId: order.id,
      screen: 'ORDER_CREATED',
    });
    // Notify eligible captains via FCM (async, non-blocking)
    this.notifyCaptainsForNewOrder({
      id: order.id,
      reference: order.reference,
      pickupLabel: order.pickupLabel,
      deliveryLabel: order.deliveryLabel,
      category: order.category,
      price: Number(order.price),
      distanceKm: Number(order.distanceKm),
      pickupLatitude: order.pickupLatitude,
      pickupLongitude: order.pickupLongitude,
    });
    return order;
  }

  /**
   * After order creation, notify eligible captains via FCM (non-blocking).
   * Runs asynchronously to not delay the client response.
   */
  private notifyCaptainsForNewOrder(order: { id: string; reference: string; pickupLabel: string; deliveryLabel: string; category: ShipmentCategory; price: number; distanceKm: number; pickupLatitude: number; pickupLongitude: number }) {
    // Fire and forget - don't await to avoid delaying the response
    this.fcm.notifyEligibleCaptains(order.id).catch((error) => {
      this.logger.error(`Failed to notify captains for order ${order.id}:`, error);
    });
  }

  listForUser(user: { id: string; role: UserRole }) {
    return this.prisma.order.findMany({
      where: user.role === UserRole.CLIENT ? { clientId: user.id } : { captainId: user.id },
      include: { client: { select: { id: true, name: true, phone: true } }, captain: { select: { id: true, name: true, phone: true } } },
      orderBy: { createdAt: 'desc' }, take: 100,
    });
  }

  async getForUser(id: string, user: { id: string; role: UserRole }) {
    const order = await this.prisma.order.findUnique({ where: { id }, include: { client: true, captain: true } });
    if (!order) throw new NotFoundException('Order not found');
    if (user.role !== UserRole.ADMIN && order.clientId !== user.id && order.captainId !== user.id) {
      throw new ForbiddenException();
    }
    return order;
  }

  /** Captain heartbeat for one active trip. Coordinates live on the profile. */
  async updateTripLocation(orderId: string, captainId: string, latitude: number, longitude: number) {
    const order = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!order) throw new NotFoundException('Order not found');
    if (order.captainId !== captainId) throw new ForbiddenException();
    if (!ACTIVE_TRIP_STATUSES.includes(order.status)) {
      throw new UnprocessableEntityException('Location is tracked only during an active trip');
    }
    await this.prisma.captainProfile.update({
      where: { userId: captainId },
      data: { lastLat: latitude, lastLng: longitude, lastSeenAt: new Date() },
    });
    try {
      await this.redis.updateCaptainLocation(captainId, latitude, longitude);
    } catch {
      // Redis is a best-effort geo index; PostgreSQL is authoritative.
    }
    return { updated: true };
  }

  /** Live captain marker for the client's tracking map. */
  async tripLocationForUser(orderId: string, user: { id: string; role: UserRole }) {
    const order = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!order) throw new NotFoundException('Order not found');
    if (user.role !== UserRole.ADMIN && order.clientId !== user.id && order.captainId !== user.id) {
      throw new ForbiddenException();
    }
    if (!order.captainId) return { latitude: null, longitude: null, seenAt: null };
    const profile = await this.prisma.captainProfile.findUnique({
      where: { userId: order.captainId },
      select: { lastLat: true, lastLng: true, lastSeenAt: true },
    });
    return {
      latitude: profile?.lastLat ?? null,
      longitude: profile?.lastLng ?? null,
      seenAt: profile?.lastSeenAt ?? null,
    };
  }

  /** Ratings use 1-5 stars. `score` is a temporary deprecated alias. */
  private resolveStars(input: RateOrderDto): number {
    let stars = input.stars;
    if (stars === undefined && input.score !== undefined) {
      ratingLogger.warn('`score` is deprecated on POST /orders/:id/rating; send `stars` (1-5) instead.');
      stars = input.score;
    }
    if (stars === undefined) throw new BadRequestException('`stars` is required (1-5)');
    if (!Number.isInteger(stars) || stars < 1 || stars > 5) {
      throw new BadRequestException('`stars` must be an integer between 1 and 5');
    }
    if (input.comment && input.comment.trim().length > 500) {
      throw new BadRequestException('`comment` must be at most 500 characters');
    }
    return stars;
  }

  /** One rating per party. The ratee is always derived from the order. */
  async rateOrder(
    orderId: string,
    user: { id: string; role: UserRole },
    input: RateOrderDto,
  ) {
    const order = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!order) throw new NotFoundException('Order not found');

    const isClient = order.clientId === user.id;
    const isCaptain = !!order.captainId && order.captainId === user.id;
    if (!isClient && !isCaptain) throw new ForbiddenException();

    if (order.status === OrderStatus.CANCELLED) {
      throw new UnprocessableEntityException('Cancelled orders cannot be rated');
    }
    if (order.status !== OrderStatus.DELIVERED && order.status !== OrderStatus.COMPLETED) {
      throw new UnprocessableEntityException('Only delivered or completed orders can be rated');
    }

    // The server derives the ratee; a body-supplied rateeId is ignored (and
    // rejected by the DTO whitelist before it ever reaches this method).
    const rateeId = isClient ? order.captainId : order.clientId;
    if (!rateeId) throw new UnprocessableEntityException('This order has no counterpart to rate');

    const stars = this.resolveStars(input);
    const existing = await this.prisma.orderRating.findUnique({
      where: { orderId_raterId: { orderId, raterId: user.id } },
    });
    if (existing) throw new ConflictException('You have already rated this order');

    try {
      return await this.prisma.$transaction(async (tx) => {
        const rating = await tx.orderRating.create({
          data: {
            orderId,
            raterId: user.id,
            rateeId,
            stars,
            comment: input.comment?.trim() || null,
          },
        });
        if (rateeId === order.captainId) {
          // Recompute from ALL of this captain's ratings inside the same
          // transaction; never a running/cumulative average.
          const aggregate = await tx.orderRating.aggregate({
            where: { rateeId },
            _avg: { stars: true },
          });
          await tx.captainProfile.updateMany({
            where: { userId: rateeId },
            data: { rating: round2(aggregate._avg.stars ?? 0) },
          });
        }
        return rating;
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new ConflictException('You have already rated this order');
      }
      throw error;
    }
  }

  async ratingForUser(orderId: string, user: { id: string; role: UserRole }) {
    const order = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!order) throw new NotFoundException('Order not found');
    if (user.role !== UserRole.ADMIN && order.clientId !== user.id && order.captainId !== user.id) {
      throw new ForbiddenException();
    }
    const rating = await this.prisma.orderRating.findFirst({
      where: {
        orderId,
        ...(user.role === UserRole.ADMIN ? {} : { raterId: user.id }),
      },
      orderBy: { createdAt: 'desc' },
    });
    if (!rating) return null;
    return {
      id: rating.id,
      orderId: rating.orderId,
      raterId: rating.raterId,
      rateeId: rating.rateeId,
      stars: rating.stars,
      // TODO(mobile phase C): read `stars`; `score` is a temporary alias.
      score: rating.stars,
      comment: rating.comment,
      createdAt: rating.createdAt,
    };
  }

  /**
   * inDrive-style feed: the captain's own coordinates decide what is shown.
   * The server keeps the location heartbeat (lastLat/lastLng/lastSeenAt), so
   * the radius filter never trusts a client-supplied radius. Orders already
   * skipped by this captain and stale searches are excluded.
   */
  async available(userId: string, latitude: number, longitude: number) {
    const captain = await this.prisma.captainProfile.findUnique({ where: { userId } });
    if (!captain || captain.status !== CaptainStatus.ACTIVE) {
      throw new ForbiddenException('Captain account is not approved');
    }
    await this.prisma.captainProfile.update({
      where: { userId },
      data: { lastLat: latitude, lastLng: longitude, lastSeenAt: new Date() },
    });
    try {
      await this.redis.updateCaptainLocation(userId, latitude, longitude);
    } catch {
      // The Redis geo index is a best-effort cache; PostgreSQL stays authoritative.
    }
    if (!captain.isOnline) return [];

    const settings = await this.prisma.pricingSettings.upsert({ where: { id: 'default' }, update: {}, create: {} });
    const wallet = await this.prisma.wallet.findUnique({
      where: { userId },
      select: { balance: true },
    });
    if (Number(wallet?.balance ?? 0) < Number(settings.minimumWalletBalance)) return [];
    const minRadius = Number(settings.minRadiusKm ?? DEFAULT_MIN_RADIUS_KM);
    const maxRadius = Number(settings.maxRadiusKm ?? DEFAULT_MAX_RADIUS_KM);
    const ownRadius = Number(captain.serviceRadiusKm) || maxRadius;
    const radiusKm = Math.max(minRadius, Math.min(ownRadius, maxRadius));

    const notExpiredSince = new Date(Date.now() - ORDER_SEARCH_EXPIRY_MINUTES * 60_000);
    const orders = await this.prisma.order.findMany({
      where: {
        status: { in: [OrderStatus.PENDING, OrderStatus.SEARCHING_CAPTAIN] },
        captainId: null,
        createdAt: { gte: notExpiredSince },
        skips: { none: { captainId: userId } },
      },
      orderBy: { createdAt: 'asc' },
      take: 50,
    });
    return orders
      .map((order) => ({
        ...order,
        distanceToPickupKm: round2(distanceKm(latitude, longitude, order.pickupLatitude, order.pickupLongitude)),
      }))
      .filter((order) => order.distanceToPickupKm <= radiusKm);
  }

  /**
   * Skip hides an order from this captain's feed permanently. Idempotent:
   * skipping twice is a no-op. Orders that are already taken or gone 409.
   */
  async skip(orderId: string, captainId: string) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: { id: true, captainId: true, status: true },
    });
    if (!order) throw new NotFoundException('Order not found');
    if (
      order.captainId ||
      (order.status !== OrderStatus.PENDING && order.status !== OrderStatus.SEARCHING_CAPTAIN)
    ) {
      throw new ConflictException('Order is no longer available');
    }
    await this.prisma.orderSkip.upsert({
      where: { orderId_captainId: { orderId, captainId } },
      update: {},
      create: { orderId, captainId },
    });
    return { skipped: true };
  }

  /**
   * Server-side expiry: unassigned searches older than the window are
   * cancelled with a SYSTEM audit event and a client notification. The
   * status-guarded updateMany makes concurrent cycles harmless.
   */
  async expireStaleSearches(limit = 50) {
    const cutoff = new Date(Date.now() - ORDER_SEARCH_EXPIRY_MINUTES * 60_000);
    const stale = await this.prisma.order.findMany({
      where: {
        status: { in: [OrderStatus.PENDING, OrderStatus.SEARCHING_CAPTAIN] },
        captainId: null,
        createdAt: { lt: cutoff },
      },
      orderBy: { createdAt: 'asc' },
      take: limit,
      select: { id: true, reference: true, clientId: true, status: true },
    });
    let expired = 0;
    for (const order of stale) {
      const cancelled = await this.prisma.$transaction(async (tx) => {
        const moved = await tx.order.updateMany({
          where: {
            id: order.id,
            captainId: null,
            status: { in: [OrderStatus.PENDING, OrderStatus.SEARCHING_CAPTAIN] },
          },
          data: { status: OrderStatus.CANCELLED },
        });
        if (!moved.count) return false;
        await this.orderEvents.record(tx, {
          orderId: order.id,
          fromStatus: order.status,
          toStatus: OrderStatus.CANCELLED,
          actorId: null,
          actorRole: EventActor.SYSTEM,
          note: 'Expired: no captain accepted within the search window',
        });
        return true;
      });
      if (!cancelled) continue;
      expired += 1;
      await this.notifyClient(order, 'لم نجد مندوبًا للطلب', `انتهت مدة البحث عن مندوب للطلب ${order.reference} وتم إلغاؤه. يمكنك إنشاء طلب جديد.`);
    }
    return { checked: stale.length, expired };
  }


  async accept(orderId: string, captainId: string) {
    const order = await this.prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      const captain = await tx.captainProfile.findUnique({ where: { userId: captainId } });
      const pricing = await tx.pricingSettings.upsert({ where: { id: 'default' }, update: {}, create: {} });
      if (!order || !captain) throw new NotFoundException('Order or captain not found');
      const captainUser = await tx.user.findUnique({ where: { id: captainId }, select: { phone: true } });
      if (!captainUser?.phone?.trim()) {
        throw new ForbiddenException({ code: 'PROFILE_INCOMPLETE', missing: ['phone'] });
      }
      if (captain.status !== 'ACTIVE') throw new ForbiddenException('Captain account is not approved');
      if ((order.status !== OrderStatus.PENDING && order.status !== OrderStatus.SEARCHING_CAPTAIN) || order.captainId) {
        throw new ConflictException('Order is no longer available');
      }
      if (!(await this.policies.hasAcknowledgement(captainId, PolicyAcknowledgementType.TERMS_CAPTAIN, { orderId: null, category: null }))) {
        throw ackRequired(PolicyAcknowledgementType.TERMS_CAPTAIN);
      }
      if (isSensitiveCategory(order.category) && !(await this.policies.hasAcknowledgement(
        captainId,
        PolicyAcknowledgementType.SENSITIVE_CATEGORY,
        { orderId, category: order.category },
      ))) {
        throw ackRequired(PolicyAcknowledgementType.SENSITIVE_CATEGORY, { orderId, category: order.category });
      }
      const required = Math.max(Number(order.commission), Number(pricing.minimumWalletBalance));
      const debit = await tx.wallet.updateMany({
        where: { userId: captainId, balance: { gte: new Prisma.Decimal(required) } },
        data: { balance: { decrement: new Prisma.Decimal(order.commission) } },
      });
      if (!debit.count) throw new UnprocessableEntityException('Insufficient wallet balance to accept this order');
      const assigned = await tx.order.updateMany({
        where: { id: orderId, captainId: null, status: { in: [OrderStatus.PENDING, OrderStatus.SEARCHING_CAPTAIN] } },
        data: { captainId, status: OrderStatus.ACCEPTED, acceptedAt: new Date() },
      });
      if (!assigned.count) throw new ConflictException('Order was accepted by another captain');
      await tx.orderSkip.deleteMany({ where: { orderId } });
      await tx.walletTransaction.create({
        data: { userId: captainId, orderId, type: WalletTransactionType.ORDER_COMMISSION, amount: new Prisma.Decimal(order.commission).negated(), note: 'Order commission reserved at acceptance' },
      });
      const updated = await tx.order.findUnique({ where: { id: orderId } });
      await this.orderEvents.record(tx, {
        orderId,
        fromStatus: order.status,
        toStatus: OrderStatus.ACCEPTED,
        actorId: captainId,
        actorRole: EventActor.CAPTAIN,
        note: 'Captain accepted the order',
      });
      return updated;
    });
    // If another captain already won, send them a cancel alert
    if (order?.captainId && order.captainId !== captainId) {
      await this.fcm.cancelTripAlert(order.id).catch(() => {
        // Best-effort notification; don't break the flow
      });
    }
    if (order) {
      await this.notifyClient(order, 'تم قبول طلبك', `قبل المندوب الطلب ${order.reference} وهو في الطريق إلى موقع الاستلام.`);
      await this.notify(captainId, 'تم قبول الطلب', `قبلت الطلب ${order.reference}. ابدأ التنقل إلى موقع الاستلام.`, NotificationType.ORDER, {
        orderId: order.id,
        screen: 'ORDER_ACCEPTED',
      });
      // Create chat room for this order
      await this.chat.createChatForOrder(order.id);
    }
    return order;
  }

  async transition(orderId: string, captainId: string, next: OrderStatus) {
    const updated = await this.prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw new NotFoundException('Order not found');
      if (order.captainId !== captainId) throw new ForbiddenException();
      this.assertAllowedTransition(order.status, next);
      // Pickup and delivery confirmations require photo proof: the direct
      // PATCH jumps below must go through POST /orders/:id/proof/pickup and
      // POST /orders/:id/proof/delivery instead. All other jumps stay allowed.
      if (
        (order.status === OrderStatus.ARRIVED_AT_PICKUP && next === OrderStatus.PICKED_UP) ||
        (order.status === OrderStatus.ON_THE_WAY && next === OrderStatus.DELIVERED)
      ) {
        throw new UnprocessableEntityException(
          'Pickup and delivery confirmations require photo proof. Use POST /orders/:id/proof/pickup or POST /orders/:id/proof/delivery.',
        );
      }
      const moved = await tx.order.update({
        where: { id: orderId },
        data: { status: next, ...(next === OrderStatus.DELIVERED ? { deliveredAt: new Date() } : {}) },
      });
      await this.orderEvents.record(tx, {
        orderId,
        fromStatus: order.status,
        toStatus: next,
        actorId: captainId,
        actorRole: EventActor.CAPTAIN,
        note: 'Captain updated the trip status',
      });
      return moved;
    });
    await this.notifyClient(updated, 'تحديث الطلب', `الطلب ${updated.reference}: ${arabicTripUpdate(next)}.`);
    return updated;
  }

  /** Single source of truth for the captain trip state machine, reused by proof submission. */
  private assertAllowedTransition(from: OrderStatus, next: OrderStatus) {
    const allowed: Partial<Record<OrderStatus, OrderStatus[]>> = {
      [OrderStatus.ACCEPTED]: [OrderStatus.ARRIVED_AT_PICKUP],
      [OrderStatus.ARRIVED_AT_PICKUP]: [OrderStatus.PICKED_UP],
      [OrderStatus.PICKED_UP]: [OrderStatus.ON_THE_WAY],
      [OrderStatus.ON_THE_WAY]: [OrderStatus.DELIVERED],
    };
    if (!allowed[from]?.includes(next)) {
      throw new UnprocessableEntityException(`Cannot move order from ${from} to ${next}`);
    }
  }

  /**
   * Proof submission shares the transition state machine: the proof row, the
   * status move, and the audit event are created in one transaction.
   * The photo file itself is written first and cannot roll back; a failed
   * transaction therefore leaves an orphan file but never inconsistent rows.
   */
  private submitProof(
    orderId: string,
    captainId: string,
    type: ProofType,
    next: OrderStatus,
    eventNote: string,
    photo?: ProofPhotoInput,
    note?: string,
  ) {
    return this.prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw new NotFoundException('Order not found');
      if (order.captainId !== captainId) throw new ForbiddenException();
      this.assertAllowedTransition(order.status, next);
      const existing = await tx.orderProof.findFirst({ where: { orderId, type } });
      if (existing) {
        throw new ConflictException(`${type === ProofType.PICKUP ? 'Pickup' : 'Delivery'} proof already submitted`);
      }
      let photoPath: string | null = null;
      if (photo) photoPath = (await saveProofPhoto(orderId, photo)).relativePath;
      await tx.orderProof.create({
        data: { orderId, type, photoPath, capturedById: captainId, note: note || undefined },
      });
      const updated = await tx.order.update({
        where: { id: orderId },
        data: { status: next, ...(next === OrderStatus.DELIVERED ? { deliveredAt: new Date() } : {}) },
      });
      await this.orderEvents.record(tx, {
        orderId,
        fromStatus: order.status,
        toStatus: next,
        actorId: captainId,
        actorRole: EventActor.CAPTAIN,
        note: eventNote,
      });
      return updated;
    });
  }

  async submitPickupProof(orderId: string, captainId: string, photo?: ProofPhotoInput, note?: string) {
    const updated = await this.submitProof(
      orderId, captainId, ProofType.PICKUP, OrderStatus.PICKED_UP, 'Pickup proof submitted', photo, note,
    );
    await this.notifyClient(updated, 'تم استلام الشحنة', `استلم المندوب شحنة الطلب ${updated.reference} وهي في الطريق إليك.`);
    return updated;
  }

  async submitDeliveryProof(orderId: string, captainId: string, photo?: ProofPhotoInput, note?: string) {
    // Commission settlement is intentionally untouched here: like a plain
    // transition to DELIVERED, no wallet movement happens; finalization still
    // occurs at client completion with the existing logic.
    const updated = await this.submitProof(
      orderId, captainId, ProofType.DELIVERY, OrderStatus.DELIVERED, 'Delivery proof submitted', photo, note,
    );
    await this.notifyClient(updated, 'تم تسليم الشحنة', `تم تسليم الطلب ${updated.reference}. يرجى تأكيد الاستلام.`);
    return updated;
  }

  async submitInvoice(orderId: string, captainId: string, input: SubmitInvoiceDto, photo?: ProofPhotoInput) {
    if (!photo) throw new BadRequestException('Invoice photo is required');
    if (!Number.isFinite(input.amount) || input.amount <= 0) throw new BadRequestException('Invoice amount must be greater than zero');
    const invoice = await this.prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw new NotFoundException('Order not found');
      if (order.captainId !== captainId) throw new ForbiddenException();
      if (order.category !== ShipmentCategory.PURCHASES && order.category !== ShipmentCategory.FOOD) {
        throw new UnprocessableEntityException('Invoices are only available for purchases and food orders');
      }
      if (order.status !== OrderStatus.PICKED_UP && order.status !== OrderStatus.ON_THE_WAY) {
        throw new UnprocessableEntityException('Invoice can only be submitted after pickup and before delivery');
      }
      const existing = await tx.purchaseInvoice.findUnique({ where: { orderId } });
      if (existing) throw new ConflictException('Invoice already submitted');
      if (order.estimatedBudget && new Prisma.Decimal(input.amount).greaterThan(order.estimatedBudget)) {
        throw new BadRequestException({ code: 'BUDGET_EXCEEDED', message: 'Invoice amount exceeds the estimated budget' });
      }
      if (!(await this.policies.hasAcknowledgement(captainId, PolicyAcknowledgementType.PURCHASE_INVOICE, { orderId }))) {
        throw ackRequired(PolicyAcknowledgementType.PURCHASE_INVOICE, { orderId });
      }
      const photoPath = (await saveProofPhoto(orderId, photo)).relativePath;
      const created = await tx.purchaseInvoice.create({
        data: {
          orderId,
          capturedById: captainId,
          amount: new Prisma.Decimal(input.amount),
          photoPath,
          note: input.note,
        },
      });
      await this.orderEvents.record(tx, {
        orderId,
        fromStatus: order.status,
        toStatus: order.status,
        actorId: captainId,
        actorRole: EventActor.CAPTAIN,
        note: 'Purchase invoice submitted',
      });
      return created;
    });
    const order = await this.prisma.order.findUnique({ where: { id: orderId }, select: { clientId: true } });
    if (order) await this.notify(order.clientId, 'فاتورة مشتريات جديدة', 'أرسل المندوب فاتورة لمراجعتها.', NotificationType.ORDER, { orderId });
    return this.sanitizeInvoice(invoice);
  }

  async respondToInvoice(orderId: string, clientId: string, input: RespondInvoiceDto) {
    if (input.action === PurchaseInvoiceStatus.DISPUTED && !input.reason?.trim()) {
      throw new BadRequestException('A reason is required to dispute an invoice');
    }
    const invoice = await this.prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw new NotFoundException('Order not found');
      if (order.clientId !== clientId) throw new ForbiddenException();
      const current = await tx.purchaseInvoice.findUnique({ where: { orderId } });
      if (!current) throw new NotFoundException('Invoice not found');
      if (current.status !== PurchaseInvoiceStatus.SUBMITTED || current.clientRespondedAt) {
        throw new ConflictException('Invoice has already received a client response');
      }
      const changed = await tx.purchaseInvoice.updateMany({
        where: { id: current.id, status: PurchaseInvoiceStatus.SUBMITTED, clientRespondedAt: null },
        data: {
          status: input.action,
          clientRespondedAt: new Date(),
          clientResponseReason: input.action === PurchaseInvoiceStatus.DISPUTED ? input.reason!.trim() : null,
        },
      });
      if (!changed.count) throw new ConflictException('Invoice has already received a client response');
      const updated = await tx.purchaseInvoice.findUnique({ where: { orderId } });
      await this.orderEvents.record(tx, {
        orderId,
        fromStatus: order.status,
        toStatus: order.status,
        actorId: clientId,
        actorRole: EventActor.CLIENT,
        note: input.action === PurchaseInvoiceStatus.CONFIRMED ? 'Client confirmed purchase invoice' : 'Client disputed purchase invoice',
      });
      return updated!;
    });
    const order = await this.prisma.order.findUnique({ where: { id: orderId }, select: { captainId: true } });
    if (order?.captainId) {
      await this.notify(order.captainId, 'رد العميل على الفاتورة', 'راجع رد العميل على فاتورة الطلب.', NotificationType.ORDER, { orderId });
    }
    return this.sanitizeInvoice(invoice);
  }

  async invoiceForUser(orderId: string, user: { id: string; role: UserRole }) {
    await this.getForUser(orderId, user);
    const invoice = await this.prisma.purchaseInvoice.findUnique({ where: { orderId } });
    if (!invoice) throw new NotFoundException('Invoice not found');
    return this.sanitizeInvoice(invoice);
  }

  async invoicePhotoForUser(orderId: string, user: { id: string; role: UserRole }) {
    await this.getForUser(orderId, user);
    const invoice = await this.prisma.purchaseInvoice.findUnique({ where: { orderId }, select: { photoPath: true } });
    const photoPath = invoice?.photoPath ? toPosixPath(invoice.photoPath) : '';
    if (!photoPath.startsWith('proofs/')) throw new NotFoundException('Invoice photo not found');
    const resolved = resolveUploadPath(photoPath);
    if (!resolved || !existsSync(resolved.path)) throw new NotFoundException('Invoice photo is missing');
    const mimeType = photoPath.endsWith('.png') ? 'image/png' : photoPath.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
    return { path: resolved.path, mimeType };
  }

  private sanitizeInvoice<T extends { photoPath: string }>(invoice: T) {
    const { photoPath, ...visible } = invoice;
    return { ...visible, hasPhoto: !!photoPath };
  }

  async complete(orderId: string, clientId: string) {
    const order = await this.prisma.$transaction(async (tx) => {
      const changed = await tx.order.updateMany({
        where: { id: orderId, clientId, status: OrderStatus.DELIVERED },
        data: { status: OrderStatus.COMPLETED, completedAt: new Date() },
      });
      if (!changed.count) throw new UnprocessableEntityException('Only the client can complete a delivered order');
      const completed = await tx.order.findUnique({ where: { id: orderId } });
      // The commission reserved at acceptance is now final: no wallet movement,
      // the held amount becomes company revenue. Count the trip for the captain.
      if (completed?.captainId) {
        await tx.captainProfile.update({
          where: { userId: completed.captainId },
          data: { totalTrips: { increment: 1 } },
        });
      }
      await this.orderEvents.record(tx, {
        orderId,
        fromStatus: OrderStatus.DELIVERED,
        toStatus: OrderStatus.COMPLETED,
        actorId: clientId,
        actorRole: EventActor.CLIENT,
        note: 'Client confirmed delivery',
      });
      return completed;
    });
    if (order?.captainId) {
      await this.notify(
        order.captainId,
        'Delivery completed',
        `Order ${order.reference} was completed. Thank you!`,
        NotificationType.ORDER,
        { orderId: order.id },
      );
      // Close chat room
      await this.chat.closeChatForOrder(order.id, 'COMPLETED');
    }
    return order;
  }

  /**
   * Client cancellation rules:
   * - Unassigned PENDING/SEARCHING_CAPTAIN -> CANCELLED, no money movement.
   * - Assigned but not yet picked up (ACCEPTED/ARRIVED_AT_PICKUP) -> CANCELLED
   *   + reserved commission refunded to the captain.
   * - PICKED_UP or later -> too late; only an admin can intervene.
   */
  async cancel(orderId: string, clientId: string) {
    const order = await this.prisma.$transaction(async (tx) => {
      const current = await tx.order.findUnique({ where: { id: orderId } });
      if (!current || current.clientId !== clientId) {
        throw new UnprocessableEntityException('This order can no longer be cancelled');
      }
      if (!current.captainId && (current.status === OrderStatus.PENDING || current.status === OrderStatus.SEARCHING_CAPTAIN)) {
        const cancelled = await tx.order.update({ where: { id: orderId }, data: { status: OrderStatus.CANCELLED } });
        await this.orderEvents.record(tx, {
          orderId,
          fromStatus: current.status,
          toStatus: OrderStatus.CANCELLED,
          actorId: clientId,
          actorRole: EventActor.CLIENT,
          note: 'Cancelled by client',
        });
        return cancelled;
      }
      if (current.captainId && (current.status === OrderStatus.ACCEPTED || current.status === OrderStatus.ARRIVED_AT_PICKUP)) {
        const cancelled = await tx.order.update({ where: { id: orderId }, data: { status: OrderStatus.CANCELLED } });
        await this.refundCommission(tx, current.captainId, current, 'Commission refunded on client cancellation');
        await this.orderEvents.record(tx, {
          orderId,
          fromStatus: current.status,
          toStatus: OrderStatus.CANCELLED,
          actorId: clientId,
          actorRole: EventActor.CLIENT,
          note: 'Cancelled by client',
        });
        return cancelled;
      }
      throw new UnprocessableEntityException('This order can no longer be cancelled');
    });
    // Send FCM cancel alert to stop any ongoing notifications
    if (order?.captainId) {
      await this.fcm.cancelTripAlert(order.id).catch(() => {
        // Best-effort; don't break the flow
      });
    }
    if (order?.captainId) {
      await this.notify(
        order.captainId,
        'Order cancelled',
        `Order ${order.reference} was cancelled by the client. The reserved commission was refunded.`,
        NotificationType.ORDER,
        { orderId: order.id },
      );
      // Close chat room
      await this.chat.closeChatForOrder(order.id, 'CANCELLED');
    }
    return order;
  }

  /**
   * Captain release rules: the assigned captain may return an order to the
   * pool before pickup (ACCEPTED/ARRIVED_AT_PICKUP). The order goes back to
   * SEARCHING_CAPTAIN and the reserved commission is refunded.
   * Chat is closed with REASSIGNED reason.
   */
  async release(orderId: string, captainId: string) {
    const order = await this.prisma.$transaction(async (tx) => {
      const current = await tx.order.findUnique({ where: { id: orderId } });
      if (!current || current.captainId !== captainId) {
        throw new UnprocessableEntityException('This order cannot be released');
      }
      if (current.status !== OrderStatus.ACCEPTED && current.status !== OrderStatus.ARRIVED_AT_PICKUP) {
        throw new UnprocessableEntityException('This order cannot be released after pickup');
      }
      const released = await tx.order.update({
        where: { id: orderId },
        data: { captainId: null, status: OrderStatus.SEARCHING_CAPTAIN, acceptedAt: null },
      });
      await this.refundCommission(tx, captainId, current, 'Commission refunded on captain release');
      await this.orderEvents.record(tx, {
        orderId,
        fromStatus: current.status,
        toStatus: OrderStatus.SEARCHING_CAPTAIN,
        actorId: captainId,
        actorRole: EventActor.CAPTAIN,
        note: 'Released by captain',
      });
      return released;
    });
    if (order) {
      await this.notifyClient(order, 'جارٍ البحث عن مندوب جديد', `اعتذر المندوب عن الطلب ${order.reference}. نبحث لك عن مندوب آخر.`);
      // Close chat room with REASSIGNED reason
      await this.chat.closeChatForOrder(order.id, 'REASSIGNED');
    }
    return order;
  }

  /**
   * Order timeline for the owning client or the assigned captain.
   * Ownership is enforced via getForUser; actor ids are stripped so neither
   * party sees the other side's internal identifiers.
   */
  async eventsForUser(id: string, user: { id: string; role: UserRole }) {
    await this.getForUser(id, user);
    const events = await this.orderEvents.list(id);
    return events.map(({ actorId: _actorId, ...event }) => event);
  }

  /**
   * Proofs visible to the owning client, the assigned captain, or an admin.
   * Internal file paths stay hidden; clients fetch photos via the dedicated
   * photo endpoint below.
   */
  async proofsForUser(id: string, user: { id: string; role: UserRole }) {
    await this.getForUser(id, user);
    const proofs = await this.prisma.orderProof.findMany({ where: { orderId: id }, orderBy: { createdAt: 'asc' } });
    return proofs.map((proof) => ({
      id: proof.id,
      type: proof.type,
      note: proof.note,
      capturedById: proof.capturedById,
      hasPhoto: !!proof.photoPath,
      createdAt: proof.createdAt,
    }));
  }

  /**
   * Resolves a proof photo for streaming. Ownership is enforced first, then
   * the stored path is confined to the proofs directory (traversal guard).
   */
  async proofPhotoForUser(orderId: string, proofId: string, user: { id: string; role: UserRole }) {
    await this.getForUser(orderId, user);
    const proof = await this.prisma.orderProof.findUnique({ where: { id: proofId } });
    const photoPath = proof?.photoPath ? toPosixPath(proof.photoPath) : '';
    if (!proof || proof.orderId !== orderId || !photoPath.startsWith('proofs/')) {
      throw new NotFoundException('Proof photo not found');
    }
    const resolved = resolveUploadPath(photoPath);
    if (!resolved || !existsSync(resolved.path)) throw new NotFoundException('Proof photo is missing');
    const mimeType = photoPath.endsWith('.png')
      ? 'image/png'
      : photoPath.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    return { path: resolved.path, mimeType };
  }

  wallet(userId: string) {
    return this.prisma.wallet.findUnique({ where: { userId }, include: { user: { select: { id: true, name: true } } } });
  }

  transactions(userId: string) {
    return this.prisma.walletTransaction.findMany({ where: { userId }, orderBy: { createdAt: 'desc' }, take: 100 });
  }
}

const sensitiveCategories: ShipmentCategory[] = [
  ShipmentCategory.MEDICINES,
  ShipmentCategory.PURCHASES,
  ShipmentCategory.FOOD,
  ShipmentCategory.ELECTRONICS,
];

function arabicTripUpdate(next: OrderStatus) {
  if (next === OrderStatus.ARRIVED_AT_PICKUP) return 'وصل المندوب إلى موقع الاستلام';
  if (next === OrderStatus.ON_THE_WAY) return 'الشحنة في الطريق إليك';
  return next;
}

function isSensitiveCategory(category: ShipmentCategory) {
  return sensitiveCategories.includes(category);
}

function ackRequired(type: PolicyAcknowledgementType, details: Record<string, string> = {}) {
  return new ForbiddenException({ code: 'ACK_REQUIRED', type, policyVersion: POLICY_VERSION, ...details });
}