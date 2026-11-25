import { ConflictException, ForbiddenException } from '@nestjs/common';
import { PolicyAcknowledgementType, ShipmentCategory, UserRole } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { POLICY_VERSION } from './policy-content.v1';
import { PoliciesService } from './policies.service';

describe('PoliciesService', () => {
  const prisma = {
    policyAcknowledgement: { upsert: jest.fn(), findFirst: jest.fn() },
    order: { findUnique: jest.fn() },
  };
  const service = new PoliciesService(prisma as unknown as PrismaService);

  beforeEach(() => jest.clearAllMocks());

  it('returns the current version and Arabic policy text', () => {
    expect(service.getPolicy('TERMS_CAPTAIN')).toMatchObject({
      type: PolicyAcknowledgementType.TERMS_CAPTAIN,
      version: POLICY_VERSION,
      title: expect.any(String),
      text: expect.any(String),
    });
  });

  it('records a policy once using a stable idempotency key', async () => {
    prisma.policyAcknowledgement.upsert.mockResolvedValue({ id: 'ack1' });
    const actor = { id: 'captain1', role: UserRole.CAPTAIN };
    const input = { type: PolicyAcknowledgementType.TERMS_CAPTAIN, policyVersion: POLICY_VERSION };

    await service.acknowledge(actor, input);
    await service.acknowledge(actor, input);

    expect(prisma.policyAcknowledgement.upsert).toHaveBeenCalledTimes(2);
    expect(prisma.policyAcknowledgement.upsert.mock.calls[0][0].where.idempotencyKey)
      .toBe(prisma.policyAcknowledgement.upsert.mock.calls[1][0].where.idempotencyKey);
    expect(prisma.policyAcknowledgement.upsert.mock.calls[0][0].update).toEqual({});
  });

  it('rejects a stale policy version', async () => {
    await expect(service.acknowledge(
      { id: 'captain1', role: UserRole.CAPTAIN },
      { type: PolicyAcknowledgementType.TERMS_CAPTAIN, policyVersion: '0.9.0' },
    )).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.policyAcknowledgement.upsert).not.toHaveBeenCalled();
  });

  it('rejects a terms acknowledgement from the wrong role', async () => {
    await expect(service.acknowledge(
      { id: 'client1', role: UserRole.CLIENT },
      { type: PolicyAcknowledgementType.TERMS_CAPTAIN, policyVersion: POLICY_VERSION },
    )).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('checks sensitive-category acknowledgement ownership and category', async () => {
    prisma.order.findUnique.mockResolvedValue({
      id: 'order1', clientId: 'client1', captainId: null, category: ShipmentCategory.FOOD,
    });
    prisma.policyAcknowledgement.upsert.mockResolvedValue({ id: 'ack2' });

    await service.acknowledge(
      { id: 'client1', role: UserRole.CLIENT },
      {
        type: PolicyAcknowledgementType.SENSITIVE_CATEGORY,
        policyVersion: POLICY_VERSION,
        category: ShipmentCategory.FOOD,
        orderId: 'order1',
      },
    );

    expect(prisma.policyAcknowledgement.upsert).toHaveBeenCalled();
  });
});