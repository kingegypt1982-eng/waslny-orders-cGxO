import { BadRequestException, UnprocessableEntityException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { CaptainStatus } from '@prisma/client';
import { AdminService } from './admin.service';
import { AdminController } from './admin.controller';
import { RolesGuard } from '../auth/roles.guard';
import { ROLES_KEY } from '../auth/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { OrderEventsService } from '../order-events/order-events.service';
import { ChatService } from '../firebase/chat.service';

describe('AdminService captain review', () => {
  const prisma = {
    captainProfile: { findUnique: jest.fn(), update: jest.fn() },
  };
  const notifications = { create: jest.fn().mockResolvedValue({ id: 'n1' }) };
  const chat = { getOrderChat: jest.fn() };
  const orderEvents = new OrderEventsService({ orderEvent: { findMany: jest.fn() } } as unknown as PrismaService);
  const service = new AdminService(
    prisma as unknown as PrismaService,
    notifications as unknown as NotificationsService,
    orderEvents,
    chat as any,
    {} as any,
  );

  const completeProfile = {
    userId: 'u1',
    status: CaptainStatus.PENDING,
    nationalIdDocument: 'captains/u1/a.jpg',
    nationalIdBackDocument: 'captains/u1/b.jpg',
    licenseDocument: 'captains/u1/c.jpg',
    licenseBackDocument: 'captains/u1/d.jpg',
    vehicleDocument: 'captains/u1/e.jpg',
    vehicleBackDocument: 'captains/u1/f.jpg',
    profilePhotoDocument: 'captains/u1/g.jpg',
  };

  beforeEach(() => jest.clearAllMocks());

  it('approves a captain with all documents uploaded and records the timestamps', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({ ...completeProfile });
    prisma.captainProfile.update.mockImplementation(async ({ data }: any) => ({ userId: 'u1', ...data }));

    const result = await service.reviewCaptain('u1', CaptainStatus.ACTIVE);

    expect(result.status).toBe(CaptainStatus.ACTIVE);
    expect(result.approvedAt).toBeInstanceOf(Date);
    expect(result.reviewedAt).toBeInstanceOf(Date);
    expect(prisma.captainProfile.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { userId: 'u1' },
        data: expect.objectContaining({
          status: CaptainStatus.ACTIVE,
          approvedAt: expect.any(Date),
          reviewedAt: expect.any(Date),
          rejectionReason: null,
        }),
      }),
    );
    expect(notifications.create).toHaveBeenCalledWith('u1', 'Account approved', expect.any(String), 'CAPTAIN', {
      screen: 'CAPTAIN_REVIEW',
      status: 'ACTIVE',
    });
  });

  it('blocks approval while a required document is missing', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({
      ...completeProfile,
      profilePhotoDocument: 'PENDING_UPLOAD',
    });

    await expect(service.reviewCaptain('u1', CaptainStatus.ACTIVE)).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(prisma.captainProfile.update).not.toHaveBeenCalled();
    expect(notifications.create).not.toHaveBeenCalled();
  });

  it('rejects with a mandatory reason, stores it, and notifies the captain with it', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({ ...completeProfile, status: CaptainStatus.PENDING });
    prisma.captainProfile.update.mockImplementation(async ({ data }: any) => ({ userId: 'u1', ...data }));

    const result = await service.reviewCaptain('u1', CaptainStatus.REJECTED, 'License image is unreadable');

    expect(result.status).toBe(CaptainStatus.REJECTED);
    expect(result.rejectionReason).toBe('License image is unreadable');
    expect(result.reviewedAt).toBeInstanceOf(Date);
    expect(notifications.create).toHaveBeenCalledWith(
      'u1',
      'Application update',
      expect.stringContaining('License image is unreadable'),
      'CAPTAIN',
      { screen: 'CAPTAIN_REVIEW', status: 'REJECTED' },
    );
  });

  it('refuses a rejection without a reason', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({ ...completeProfile });

    await expect(service.reviewCaptain('u1', CaptainStatus.REJECTED)).rejects.toBeInstanceOf(BadRequestException);
    await expect(service.reviewCaptain('u1', CaptainStatus.REJECTED, '  ')).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.captainProfile.update).not.toHaveBeenCalled();
  });

  it('restores a suspended captain without re-checking documents', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({
      userId: 'u1',
      status: CaptainStatus.SUSPENDED,
      nationalIdDocument: 'PENDING_UPLOAD',
      nationalIdBackDocument: 'PENDING_UPLOAD',
      licenseDocument: 'PENDING_UPLOAD',
      licenseBackDocument: 'PENDING_UPLOAD',
      vehicleDocument: 'PENDING_UPLOAD',
      vehicleBackDocument: 'PENDING_UPLOAD',
      profilePhotoDocument: 'PENDING_UPLOAD',
    });
    prisma.captainProfile.update.mockImplementation(async ({ data }: any) => ({ userId: 'u1', ...data }));

    const result = await service.reviewCaptain('u1', CaptainStatus.ACTIVE);

    expect(result.status).toBe(CaptainStatus.ACTIVE);
    expect(notifications.create).toHaveBeenCalledWith('u1', 'Account restored', expect.any(String), 'CAPTAIN', {
      screen: 'CAPTAIN_REVIEW',
      status: 'ACTIVE',
    });
  });
});

describe('Admin captain review endpoints require the ADMIN role', () => {
  it('declares ADMIN on the controller', () => {
    const roles = Reflect.getMetadata(ROLES_KEY, AdminController) as string[] | undefined;
    expect(roles).toContain('ADMIN');
  });

  it('denies non-admin users and allows admins', () => {
    const guard = new RolesGuard(new Reflector());
    const context = (role: string) => ({
      getHandler: () => AdminController.prototype.reject,
      getClass: () => AdminController,
      switchToHttp: () => ({ getRequest: () => ({ user: { role } }) }),
    }) as any;

    expect(guard.canActivate(context('CLIENT'))).toBe(false);
    expect(guard.canActivate(context('CAPTAIN'))).toBe(false);
    expect(guard.canActivate(context('ADMIN'))).toBe(true);
  });
});
