import { BadRequestException, ConflictException, ForbiddenException } from '@nestjs/common';
import { CaptainsController } from './captains.controller';
import { NationalIdCryptoService } from './national-id-crypto.service';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.module';

jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  existsSync: jest.fn().mockReturnValue(true),
  createReadStream: jest.fn().mockReturnValue('stream'),
}));
jest.mock('fs/promises', () => ({
  mkdir: jest.fn().mockResolvedValue(undefined),
  writeFile: jest.fn().mockResolvedValue(undefined),
}));

describe('CaptainsController profile', () => {
  const prisma = {
    captainProfile: { findUnique: jest.fn(), findFirst: jest.fn(), update: jest.fn() },
    pricingSettings: { findUnique: jest.fn(), upsert: jest.fn() },
    wallet: { findUnique: jest.fn() },
  };
  const redis = { updateCaptainLocation: jest.fn() };
  const fcm = {
    sendTripAlert: jest.fn().mockResolvedValue(true),
    notifyEligibleCaptains: jest.fn().mockResolvedValue(0),
    cancelTripAlert: jest.fn().mockResolvedValue(undefined),
    registerFcmToken: jest.fn().mockResolvedValue(undefined),
    clearFcmToken: jest.fn().mockResolvedValue(undefined),
  };
  const originalKey = process.env.NATIONAL_ID_ENCRYPTION_KEY;
  let crypto: NationalIdCryptoService;
  let controller: CaptainsController;

  beforeAll(() => {
    process.env.NATIONAL_ID_ENCRYPTION_KEY = Buffer.from('k'.repeat(32)).toString('base64');
    crypto = new NationalIdCryptoService();
    controller = new CaptainsController(
      prisma as unknown as PrismaService,
      redis as unknown as RedisService,
      crypto,
      fcm as any,
    );
  });

  afterAll(() => {
    if (originalKey === undefined) delete process.env.NATIONAL_ID_ENCRYPTION_KEY;
    else process.env.NATIONAL_ID_ENCRYPTION_KEY = originalKey;
  });

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.pricingSettings.findUnique.mockResolvedValue({
      minRadiusKm: 2,
      maxRadiusKm: 15,
      minimumWalletBalance: 75,
    });
    prisma.pricingSettings.upsert.mockResolvedValue({ minRadiusKm: 2, maxRadiusKm: 15 });
  });

  it('rejects an invalid national ID', async () => {
    await expect(
      controller.updateProfile({ id: 'u1' }, { nationalId: '123' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('includes the configured minimum wallet balance in the wallet response', async () => {
    prisma.wallet.findUnique.mockResolvedValue({ balance: 40, user: { walletTransactions: [] } });

    await expect(controller.wallet({ id: 'u1' })).resolves.toMatchObject({
      balance: 40,
      minimumWalletBalance: 75,
    });
    expect(prisma.pricingSettings.findUnique).toHaveBeenCalledWith({ where: { id: 'default' } });
    expect(prisma.pricingSettings.upsert).not.toHaveBeenCalled();
  });

  it('rejects a duplicate national ID with 409 and does not reveal the other account', async () => {
    prisma.captainProfile.findFirst.mockResolvedValue({ userId: 'someone-else' });
    let caught: any;
    try {
      await controller.updateProfile({ id: 'u1' }, { nationalId: '30201011234567' });
    } catch (err) {
      caught = err;
    }
    expect(caught).toBeInstanceOf(ConflictException);
    expect(caught.getResponse()).toMatchObject({ code: 'NATIONAL_ID_DUPLICATE' });
    expect(JSON.stringify(caught.getResponse())).not.toContain('someone-else');
  });

  it('stores encrypted national ID and returns only the masked last4', async () => {
    prisma.captainProfile.findFirst.mockResolvedValue(null);
    prisma.captainProfile.update.mockImplementation(async ({ data }: any) => ({
      id: 'p1',
      userId: 'u1',
      status: 'PENDING',
      dateOfBirth: data.dateOfBirth,
      governorate: data.governorate,
      licenseNumber: data.licenseNumber,
      vehicleRegistrationNumber: data.vehicleRegistrationNumber,
      nationalIdLast4: data.nationalIdLast4,
    }));

    const result = (await controller.updateProfile(
      { id: 'u1' },
      { nationalId: '30201011234567', governorate: 'Cairo' },
    )) as any;

    expect(result.nationalIdLast4).toBe('4567');
    expect(result.nationalIdEncrypted).toBeUndefined();
    expect(JSON.stringify(result)).not.toContain('30201011234567');

    const stored = prisma.captainProfile.update.mock.calls[0][0].data;
    expect(stored.nationalIdEncrypted).toBeDefined();
    expect(crypto.decrypt(stored.nationalIdEncrypted)).toBe('30201011234567');
    expect(stored.nationalIdHash).toBe(crypto.hash('30201011234567'));
  });

  it('GET /me masks the encrypted national ID and lists missing fields', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({
      id: 'p1',
      userId: 'u1',
      status: 'PENDING',
      nationalIdEncrypted: crypto.encrypt('30201011234567'),
      nationalIdHash: crypto.hash('30201011234567'),
      nationalIdLast4: '4567',
      governorate: null,
      licenseNumber: null,
      vehicleRegistrationNumber: null,
      dateOfBirth: null,
      vehicleType: null,
      vehiclePlate: null,
      vehicleMake: null,
      vehicleColor: null,
      profilePhotoDocument: 'PENDING_UPLOAD',
      user: { id: 'u1', name: 'Cap', email: 'c@x.com', phone: null, wallet: null },
    });

    const result = (await controller.profile({ id: 'u1' })) as any;
    expect(result.nationalIdEncrypted).toBeUndefined();
    expect(result.nationalIdHash).toBeUndefined();
    expect(result.nationalIdLast4).toBe('4567');
    expect(result.missing).toEqual(
      expect.arrayContaining([
        'phone',
        'governorate',
        'licenseNumber',
        'vehicleRegistrationNumber',
        'dateOfBirth',
        'vehicle',
        'vehicleDetails',
        'profilePhoto',
      ]),
    );
    expect(result.missing).not.toContain('nationalId');
    expect(result.radiusBand).toEqual({ min: 2, max: 15 });
  });

  it('uses safe defaults when the pricing settings row is absent', async () => {
    prisma.pricingSettings.findUnique.mockResolvedValue(null);
    prisma.captainProfile.findUnique.mockResolvedValue({
      id: 'p1',
      userId: 'u1',
      status: 'ACTIVE',
      user: { id: 'u1', phone: '01000000000', wallet: null },
    });
    prisma.wallet.findUnique.mockResolvedValue({ balance: 0, user: { walletTransactions: [] } });

    const profileResult = (await controller.profile({ id: 'u1' })) as any;
    expect(profileResult.radiusBand).toEqual({ min: 0.5, max: 15 });

    await expect(controller.wallet({ id: 'u1' })).resolves.toMatchObject({
      balance: 0,
      minimumWalletBalance: 0,
    });
    expect(prisma.pricingSettings.upsert).not.toHaveBeenCalled();
  });

  it('accepts vehicle make/model/color and plate through the profile update', async () => {
    prisma.captainProfile.findFirst.mockResolvedValue(null);
    prisma.captainProfile.update.mockImplementation(async ({ data }: any) => ({
      id: 'p1',
      userId: 'u1',
      status: 'PENDING',
      vehiclePlate: data.vehiclePlate,
      vehicleMake: data.vehicleMake,
      vehicleModel: data.vehicleModel,
      vehicleColor: data.vehicleColor,
      vehicleRegistrationNumber: data.vehicleRegistrationNumber,
    }));

    const result = (await controller.updateProfile(
      { id: 'u1' },
      {
        vehicleRegistrationNumber: '12345',
        vehiclePlate: '2173 ج ك ب',
        vehicleMake: 'Honda',
        vehicleModel: 'CB 1100',
        vehicleColor: 'أبيض',
      },
    )) as any;

    expect(result.vehicleRegistrationNumber).toBe('12345');
    expect(result.vehiclePlate).toBe('2173 ج ك ب');
    expect(result.vehicleMake).toBe('Honda');
    expect(result.vehicleModel).toBe('CB 1100');
    expect(result.vehicleColor).toBe('أبيض');

    const stored = prisma.captainProfile.update.mock.calls[0][0].data;
    expect(stored.vehiclePlate).toBe('2173 ج ك ب');
    expect(stored.vehicleMake).toBe('Honda');
    expect(stored.vehicleColor).toBe('أبيض');
  });

  it.each([
    ['identity', 'nationalIdDocument'],
    ['identity-back', 'nationalIdBackDocument'],
    ['license', 'licenseDocument'],
    ['license-back', 'licenseBackDocument'],
    ['vehicle', 'vehicleDocument'],
    ['vehicle-back', 'vehicleBackDocument'],
    ['profile-photo', 'profilePhotoDocument'],
  ])('stores %s documents in the %s field', async (type, field) => {
    prisma.captainProfile.update.mockResolvedValue({});
    const file = { mimetype: 'image/jpeg', buffer: Buffer.from('x') } as any;

    await controller.uploadDocument({ id: 'u1' }, type, file);

    expect(prisma.captainProfile.update).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      data: { [field]: expect.stringContaining('captains') },
    });
  });

  it('rejects unknown document types', async () => {
    const file = { mimetype: 'image/jpeg', buffer: Buffer.from('x') } as any;
    await expect(
      controller.uploadDocument({ id: 'u1' }, 'passport', file),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('GET /me/documents/:type serves the captain own uploaded document', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({
      profilePhotoDocument: 'captains/u1/photo.jpg',
    });
    const stream = await controller.myDocument({ id: 'u1' }, 'profile-photo');
    expect(stream).toBeDefined();
  });

  it('stores uploaded paths with forward slashes even where path.join uses backslashes', async () => {
    prisma.captainProfile.update.mockResolvedValue({});
    const file = { mimetype: 'image/jpeg', buffer: Buffer.from('x') } as any;

    await controller.uploadDocument({ id: 'u1' }, 'identity', file);

    const stored = prisma.captainProfile.update.mock.calls[0][0].data.nationalIdDocument;
    expect(stored).toMatch(/^captains\/u1\/.+\.jpg$/);
  });

  it('serves documents stored under Windows backslash separators', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({
      profilePhotoDocument: 'captains\\u1\\photo.jpg',
    });
    const stream = await controller.myDocument({ id: 'u1' }, 'profile-photo');
    expect(stream).toBeDefined();
  });

  it('rejects documents stored under another captain', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({
      profilePhotoDocument: 'captains\\someone-else\\photo.jpg',
    });
    await expect(
      controller.myDocument({ id: 'u1' }, 'profile-photo'),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('GET /me/documents/:type rejects un-uploaded documents', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({
      profilePhotoDocument: 'PENDING_UPLOAD',
    });
    await expect(
      controller.myDocument({ id: 'u1' }, 'profile-photo'),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('only an approved captain can go online', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({ status: 'PENDING' });

    await expect(
      controller.availability({ id: 'u1' }, { isOnline: true }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.captainProfile.update).not.toHaveBeenCalled();
  });

  it('rejects a service radius outside the admin-configured band', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    prisma.pricingSettings.upsert.mockResolvedValue({ minRadiusKm: 2, maxRadiusKm: 15 });

    await expect(
      controller.availability({ id: 'u1' }, { isOnline: true, serviceRadiusKm: 40 }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.captainProfile.update).not.toHaveBeenCalled();
  });

  it('toggles availability and persists the location heartbeat', async () => {
    prisma.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    prisma.pricingSettings.upsert.mockResolvedValue({ minRadiusKm: 2, maxRadiusKm: 15 });
    prisma.captainProfile.update.mockResolvedValue({ isOnline: true, serviceRadiusKm: 8 });

    await controller.availability({ id: 'u1' }, { isOnline: true, serviceRadiusKm: 8 });
    expect(prisma.captainProfile.update).toHaveBeenCalledWith(expect.objectContaining({
      where: { userId: 'u1' },
      data: { isOnline: true, serviceRadiusKm: 8 },
    }));

    redis.updateCaptainLocation.mockResolvedValue(true);
    prisma.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    await controller.location({ id: 'u1' }, { latitude: 30.1, longitude: 31.2 });
    expect(prisma.captainProfile.update).toHaveBeenCalledWith(expect.objectContaining({
      where: { userId: 'u1' },
      data: expect.objectContaining({ lastLat: 30.1, lastLng: 31.2, lastSeenAt: expect.any(Date) }),
    }));
  });

  it('keeps the location heartbeat when Redis is unavailable', async () => {
    const warn = jest.spyOn((controller as any).logger, 'warn').mockImplementation(() => undefined);
    prisma.captainProfile.findUnique.mockResolvedValue({ status: 'ACTIVE' });
    prisma.captainProfile.update.mockResolvedValue({});
    redis.updateCaptainLocation.mockRejectedValue(new Error('geoadd failed'));

    await expect(
      controller.location({ id: 'u1' }, { latitude: 30.1, longitude: 31.2 }),
    ).resolves.toEqual({ updated: false, reason: 'Location saved; live index unavailable' });
    expect(prisma.captainProfile.update).toHaveBeenCalledWith(expect.objectContaining({
      where: { userId: 'u1' },
      data: expect.objectContaining({ lastLat: 30.1, lastLng: 31.2, lastSeenAt: expect.any(Date) }),
    }));
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('Redis captain location update failed'));
    warn.mockRestore();
  });
});
