import { ConflictException, UnauthorizedException, ValidationPipe } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { AuthService } from './auth.service';
import { GoogleLoginDto } from './dto/google-login.dto';
import { RegisterDto } from './dto/register.dto';
import { PrismaService } from '../prisma/prisma.service';

jest.mock('google-auth-library', () => {
  const verifyIdToken = jest.fn();
  const OAuth2ClientMock = jest.fn().mockImplementation(() => ({ verifyIdToken }));
  return { OAuth2Client: OAuth2ClientMock, __mockVerifyIdToken: verifyIdToken };
});

const mockedAuthLibrary = jest.requireMock('google-auth-library') as {
  OAuth2Client: jest.Mock;
  __mockVerifyIdToken: jest.Mock;
};
const mockVerifyIdToken = mockedAuthLibrary.__mockVerifyIdToken;
const mockOAuth2Client = mockedAuthLibrary.OAuth2Client;

describe('Google sign-in', () => {
  const prisma = {
    user: { findUnique: jest.fn(), create: jest.fn(), update: jest.fn() },
  };
  const jwt = { signAsync: jest.fn().mockResolvedValue('signed-token') };
  const service = new AuthService(
    prisma as unknown as PrismaService,
    jwt as unknown as JwtService,
  );
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const savedClientId = process.env.GOOGLE_CLIENT_ID;

  const validPayload = {
    sub: 'google-123',
    email: 'GUser@Waslny.com',
    email_verified: true,
    name: 'G User',
  };

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.GOOGLE_CLIENT_ID = 'test-web-client-id';
    mockVerifyIdToken.mockResolvedValue({
      getPayload: () => ({ ...validPayload }),
    });
  });

  afterEach(() => {
    if (savedClientId === undefined) delete process.env.GOOGLE_CLIENT_ID;
    else process.env.GOOGLE_CLIENT_ID = savedClientId;
  });

  it('creates a client without phone and reports missing phone', async () => {
    prisma.user.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ phone: null, captain: null });
    prisma.user.create.mockImplementation(async ({ data }: any) => ({ id: 'u9', ...data }));

    const result = await service.googleLogin({ idToken: 'tok', role: 'CLIENT', termsAccepted: true });

    expect(prisma.user.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          email: 'guser@waslny.com',
          passwordHash: null,
          googleId: 'google-123',
          role: 'CLIENT',
        }),
      }),
    );
    expect(result).toMatchObject({ accessToken: 'signed-token', missing: ['phone'] });
  });

  it('creates a captain with null vehicle and reports phone+vehicle missing', async () => {
    prisma.user.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ phone: null, captain: { vehicleType: null, vehiclePlate: null } });
    prisma.user.create.mockImplementation(async ({ data }: any) => ({ id: 'u10', ...data, role: 'CAPTAIN' }));

    const result = await service.googleLogin({ idToken: 'tok', role: 'CAPTAIN', termsAccepted: true });

    const data = prisma.user.create.mock.calls[0][0].data;
    expect(data.captain.create.vehicleType).toBeNull();
    expect(data.captain.create.vehiclePlate).toBeNull();
    expect(result.missing).toEqual(['phone', 'vehicle']);
  });

  it('signs in an account already linked to the same Google identity', async () => {
    prisma.user.findUnique
      .mockResolvedValueOnce({ id: 'u1', email: 'guser@waslny.com', name: 'G', role: 'CLIENT', googleId: 'google-123', passwordHash: null, suspendedAt: null })
      .mockResolvedValueOnce({ phone: '+201000000000', captain: null });

    const result = await service.googleLogin({ idToken: 'tok', role: 'CLIENT' });

    expect(prisma.user.update).not.toHaveBeenCalled();
    expect(prisma.user.create).not.toHaveBeenCalled();
    expect(result).toMatchObject({ accessToken: 'signed-token' });
  });

  it('refuses to link an existing password account instead of taking it over', async () => {
    const passwordHash = '$2b$12$notARealHashJustForTheMock';
    const existing = {
      id: 'u1',
      email: 'guser@waslny.com',
      name: 'G',
      role: 'CLIENT',
      googleId: null,
      passwordHash,
      suspendedAt: null,
    };
    prisma.user.findUnique.mockResolvedValueOnce(existing);

    const error = await service.googleLogin({ idToken: 'tok', role: 'CLIENT' }).catch((e) => e);

    expect(error).toBeInstanceOf(ConflictException);
    expect(error.getStatus()).toBe(409);
    expect(error.response).toMatchObject({ code: 'EMAIL_USES_PASSWORD_LOGIN' });
    // No linking write, no new account, no session, and the password stays.
    expect(prisma.user.update).not.toHaveBeenCalled();
    expect(prisma.user.create).not.toHaveBeenCalled();
    expect(jwt.signAsync).not.toHaveBeenCalled();
    expect(existing.passwordHash).toBe(passwordHash);
    expect(existing.googleId).toBeNull();
  });

  it('still links an account that has no password and no Google identity', async () => {
    prisma.user.findUnique
      .mockResolvedValueOnce({ id: 'u2', email: 'guser@waslny.com', name: 'G', role: 'CLIENT', googleId: null, passwordHash: null, suspendedAt: null })
      .mockResolvedValueOnce({ phone: '+201000000000', captain: null });
    prisma.user.update.mockImplementation(async ({ data }: any) => ({ id: 'u2', email: 'guser@waslny.com', name: 'G', role: 'CLIENT', ...data }));

    const result = await service.googleLogin({ idToken: 'tok', role: 'CLIENT' });

    expect(prisma.user.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: { googleId: 'google-123' } }),
    );
    expect(result).toMatchObject({ accessToken: 'signed-token' });
  });

  it('rejects unverified emails', async () => {
    mockVerifyIdToken.mockResolvedValue({
      getPayload: () => ({ ...validPayload, email_verified: false }),
    });
    await expect(service.googleLogin({ idToken: 'tok', role: 'CLIENT' })).rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.user.findUnique).not.toHaveBeenCalled();
  });

  it('rejects tampered tokens', async () => {
    mockVerifyIdToken.mockRejectedValue(new Error('bad signature'));
    const error = await service.googleLogin({ idToken: 'tok', role: 'CLIENT' }).catch((e) => e);
    expect(error).toBeInstanceOf(UnauthorizedException);
    expect(error.getStatus()).toBe(401);
    expect(error.message).toBe('Invalid Google credential');
    expect(mockVerifyIdToken).toHaveBeenCalledWith({
      idToken: 'tok',
      audience: 'test-web-client-id',
    });
  });

  it('requires terms before creating a new Google account', async () => {
    prisma.user.findUnique.mockResolvedValueOnce(null);
    const error = await service.googleLogin({
      idToken: 'tok',
      role: 'CLIENT',
      termsAccepted: false,
    }).catch((e) => e);

    expect(error.getStatus()).toBe(400);
    expect(error.response).toMatchObject({ code: 'TERMS_REQUIRED' });
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('refuses clearly when GOOGLE_CLIENT_ID is not configured', async () => {
    delete process.env.GOOGLE_CLIENT_ID;
    await expect(service.googleLogin({ idToken: 'tok', role: 'CLIENT' })).rejects.toMatchObject({
      message: expect.stringContaining('GOOGLE_CLIENT_ID'),
    });
    expect(mockOAuth2Client).not.toHaveBeenCalled();
  });

  it('rejects ADMIN and unknown roles at the DTO level', async () => {
    await expect(
      pipe.transform({ idToken: 'test-id-token-123', role: 'ADMIN' }, { type: 'body', metatype: GoogleLoginDto }),
    ).rejects.toBeDefined();
    await expect(
      pipe.transform({ idToken: 'test-id-token-123', role: 'CLIENT' }, { type: 'body', metatype: GoogleLoginDto }),
    ).resolves.toMatchObject({ role: 'CLIENT' });
  });

  it('rejects a different linked Google account with 409', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'u1', email: 'guser@waslny.com', name: 'G', role: 'CLIENT', googleId: 'google-999', suspendedAt: null,
    });
    const error = await service.googleLogin({ idToken: 'tok', role: 'CLIENT' }).catch((e) => e);
    expect(error).toBeInstanceOf(ConflictException);
    expect(error?.response).toMatchObject({ code: 'GOOGLE_ACCOUNT_MISMATCH' });
    expect(prisma.user.update).not.toHaveBeenCalled();
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('rejects suspended accounts like password login', async () => {
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', suspendedAt: new Date() });
    await expect(service.googleLogin({ idToken: 'tok', role: 'CLIENT' })).rejects.toMatchObject({
      message: 'Invalid email or password',
    });
  });

  it('password login on a passwordless Google account fails safely', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'u9', email: 'guser@waslny.com', name: 'G', role: 'CLIENT', suspendedAt: null, passwordHash: null,
    });
    await expect(
      service.login({ email: 'guser@waslny.com', password: 'Whatever123' }),
    ).rejects.toMatchObject({ message: 'Invalid email or password' });
  });
});

describe('RegisterDto phone requirement', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const base = { email: 'a@b.com', password: 'Secret123', name: 'AB', role: 'CLIENT' };

  it('rejects a missing phone', async () => {
    await expect(
      pipe.transform({ ...base }, { type: 'body', metatype: RegisterDto }),
    ).rejects.toBeDefined();
  });

  it('rejects a non-Egyptian phone', async () => {
    await expect(
      pipe.transform({ ...base, phone: '12345' }, { type: 'body', metatype: RegisterDto }),
    ).rejects.toBeDefined();
  });

  it('accepts an Egyptian phone', async () => {
    await expect(
      pipe.transform({ ...base, phone: '01000000000' }, { type: 'body', metatype: RegisterDto }),
    ).resolves.toMatchObject({ phone: '01000000000' });
  });
});
