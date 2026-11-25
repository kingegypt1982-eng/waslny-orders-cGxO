import { ConflictException, ValidationPipe } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { GoogleLoginDto } from './dto/google-login.dto';
import { PrismaService } from '../prisma/prisma.service';

jest.mock('google-auth-library', () => {
  const verifyIdToken = jest.fn();
  const OAuth2ClientMock = jest.fn().mockImplementation(() => ({ verifyIdToken }));
  return { OAuth2Client: OAuth2ClientMock, __mockVerifyIdToken: verifyIdToken };
});

const mockVerifyIdToken = (jest.requireMock('google-auth-library') as {
  __mockVerifyIdToken: jest.Mock;
}).__mockVerifyIdToken;

/**
 * Controller-level checks for POST /auth/google. Follows the same style as
 * google-config.spec.ts (instantiate the controller directly) so the test does
 * not need a live server or database; the DTO goes through the real
 * ValidationPipe exactly like the HTTP layer.
 */
describe('POST /auth/google (endpoint)', () => {
  const prisma = {
    user: { findUnique: jest.fn(), create: jest.fn(), update: jest.fn() },
  };
  const jwt = { signAsync: jest.fn().mockResolvedValue('signed-token') };
  const service = new AuthService(
    prisma as unknown as PrismaService,
    jwt as unknown as JwtService,
  );
  const controller = new AuthController(service);
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const savedClientId = process.env.GOOGLE_CLIENT_ID;

  const call = async (body: Record<string, unknown>) => {
    const dto = (await pipe.transform(body, {
      type: 'body',
      metatype: GoogleLoginDto,
    })) as GoogleLoginDto;
    return controller.google(dto);
  };

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.GOOGLE_CLIENT_ID = 'test-web-client-id';
    mockVerifyIdToken.mockResolvedValue({
      getPayload: () => ({
        sub: 'google-123',
        email: 'endpoint-user@waslny.com',
        email_verified: true,
        name: 'Endpoint User',
      }),
    });
  });

  afterEach(() => {
    if (savedClientId === undefined) delete process.env.GOOGLE_CLIENT_ID;
    else process.env.GOOGLE_CLIENT_ID = savedClientId;
  });

  it('answers 409 EMAIL_USES_PASSWORD_LOGIN for a password account and issues no session', async () => {
    prisma.user.findUnique.mockResolvedValueOnce({
      id: 'u1',
      email: 'endpoint-user@waslny.com',
      name: 'Endpoint User',
      role: 'CLIENT',
      googleId: null,
      passwordHash: '$2b$12$notARealHashJustForTheMock',
      suspendedAt: null,
    });

    const error = await call({
      idToken: 'google-id-token',
      role: 'CLIENT',
    }).catch((e) => e);

    expect(error).toBeInstanceOf(ConflictException);
    expect(error.getStatus()).toBe(409);
    expect(error.response).toMatchObject({ code: 'EMAIL_USES_PASSWORD_LOGIN' });
    expect(prisma.user.update).not.toHaveBeenCalled();
    expect(prisma.user.create).not.toHaveBeenCalled();
    expect(jwt.signAsync).not.toHaveBeenCalled();
  });

  it('creates a new account with accepted terms and returns the session', async () => {
    prisma.user.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ phone: '+201000000000', captain: null });
    prisma.user.create.mockImplementation(async ({ data }: any) => ({ id: 'u9', ...data }));

    const result = await call({
      idToken: 'google-id-token',
      role: 'CLIENT',
      termsAccepted: true,
    });

    expect(prisma.user.create).toHaveBeenCalledTimes(1);
    expect(result).toMatchObject({
      accessToken: 'signed-token',
      user: { id: 'u9', email: 'endpoint-user@waslny.com', role: 'CLIENT' },
    });
  });

  it('answers 400 TERMS_REQUIRED for a new account without accepted terms', async () => {
    prisma.user.findUnique.mockResolvedValueOnce(null);

    const error = await call({
      idToken: 'google-id-token',
      role: 'CLIENT',
    }).catch((e) => e);

    expect(error.getStatus()).toBe(400);
    expect(error.response).toMatchObject({ code: 'TERMS_REQUIRED' });
    expect(prisma.user.create).not.toHaveBeenCalled();
  });
});
