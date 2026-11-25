import { createHash } from 'crypto';
import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PolicyAcknowledgementType, ShipmentCategory, UserRole } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AcknowledgePolicyDto } from './acknowledge-policy.dto';
import { POLICY_CONTENT, POLICY_VERSION } from './policy-content.v1';

export type PolicyActor = { id: string; role: UserRole };

@Injectable()
export class PoliciesService {
  constructor(private readonly prisma: PrismaService) {}

  getPolicy(type: string) {
    const policyType = type as PolicyAcknowledgementType;
    const content = POLICY_CONTENT[policyType];
    if (!content) throw new NotFoundException('Policy not found');
    return { type: policyType, version: POLICY_VERSION, ...content };
  }

  async acknowledge(user: PolicyActor, input: AcknowledgePolicyDto) {
    const policy = this.getPolicy(input.type);
    if (input.policyVersion !== policy.version) {
      throw new ConflictException({ code: 'POLICY_VERSION_MISMATCH', currentVersion: policy.version });
    }

    if (input.type === PolicyAcknowledgementType.TERMS_CAPTAIN && user.role !== UserRole.CAPTAIN) {
      throw new ForbiddenException('Captain terms are only available to captains');
    }
    if (input.type === PolicyAcknowledgementType.TERMS_CLIENT && user.role !== UserRole.CLIENT) {
      throw new ForbiddenException('Client terms are only available to clients');
    }
    if (input.type === PolicyAcknowledgementType.SENSITIVE_CATEGORY) {
      if (!input.category || (user.role !== UserRole.CLIENT && user.role !== UserRole.CAPTAIN)) {
        throw new ForbiddenException('A client or captain category acknowledgement is required');
      }
      if (input.orderId) await this.validateOrderAcknowledgement(user, input.orderId, input.category);
    } else if (input.type === PolicyAcknowledgementType.PURCHASE_INVOICE) {
      if (user.role !== UserRole.CAPTAIN || !input.orderId) {
        throw new ForbiddenException('An assigned captain and order are required');
      }
      await this.validateInvoiceAcknowledgement(user.id, input.orderId, input.category);
    } else if (input.orderId || input.category) {
      throw new ConflictException('This policy does not accept an order or category');
    }

    const idempotencyKey = createHash('sha256')
      .update([user.id, input.type, input.policyVersion, input.orderId ?? '', input.category ?? ''].join('\0'))
      .digest('hex');

    return this.prisma.policyAcknowledgement.upsert({
      where: { idempotencyKey },
      create: {
        userId: user.id,
        type: input.type,
        policyVersion: input.policyVersion,
        orderId: input.orderId,
        category: input.category,
        idempotencyKey,
      },
      update: {},
      select: { id: true, type: true, policyVersion: true, orderId: true, category: true, createdAt: true },
    });
  }

  hasAcknowledgement(
    userId: string,
    type: PolicyAcknowledgementType,
    scope: { orderId?: string | null; category?: ShipmentCategory | null } = {},
  ) {
    return this.prisma.policyAcknowledgement.findFirst({
      where: {
        userId,
        type,
        policyVersion: POLICY_VERSION,
        ...('orderId' in scope ? { orderId: scope.orderId } : {}),
        ...('category' in scope ? { category: scope.category } : {}),
      },
      select: { id: true },
    });
  }

  private async validateOrderAcknowledgement(user: PolicyActor, orderId: string, category: ShipmentCategory) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: { id: true, clientId: true, captainId: true, category: true },
    });
    if (!order) throw new NotFoundException('Order not found');
    if (order.category !== category) throw new ConflictException('Acknowledged category does not match the order');
    if (user.role === UserRole.CLIENT && order.clientId !== user.id) throw new ForbiddenException();
    if (user.role === UserRole.CAPTAIN && order.captainId && order.captainId !== user.id) throw new ForbiddenException();
  }

  private async validateInvoiceAcknowledgement(userId: string, orderId: string, category?: ShipmentCategory) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: { captainId: true, category: true },
    });
    if (!order) throw new NotFoundException('Order not found');
    const invoiceCategories: ShipmentCategory[] = [ShipmentCategory.PURCHASES, ShipmentCategory.FOOD];
    if (order.captainId !== userId || !invoiceCategories.includes(order.category)) {
      throw new ForbiddenException();
    }
    if (category && category !== order.category) throw new ConflictException('Acknowledged category does not match the order');
  }
}