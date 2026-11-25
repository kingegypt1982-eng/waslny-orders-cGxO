import { Injectable } from '@nestjs/common';
import { EventActor, OrderStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

export interface RecordOrderEventInput {
  orderId: string;
  fromStatus: OrderStatus | null;
  toStatus: OrderStatus;
  actorId?: string | null;
  actorRole: EventActor;
  note?: string;
}

@Injectable()
export class OrderEventsService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Appends one audit event. Must be called with the same transaction client
   * that performs the status change, so the event and the change are atomic:
   * if the change fails, no event is left behind, and vice versa.
   */
  record(tx: Prisma.TransactionClient, input: RecordOrderEventInput) {
    return tx.orderEvent.create({
      data: {
        orderId: input.orderId,
        fromStatus: input.fromStatus,
        toStatus: input.toStatus,
        actorId: input.actorId ?? null,
        actorRole: input.actorRole,
        note: input.note,
      },
    });
  }

  list(orderId: string) {
    return this.prisma.orderEvent.findMany({
      where: { orderId },
      orderBy: { createdAt: 'asc' },
    });
  }
}
