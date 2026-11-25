import { UnauthorizedException, ValidationPipe } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { PrismaService } from '../prisma/prisma.service';

describe('Password reset (link-based)', () => {
  const prisma = {
    user: { findUnique: jest.fn(), update: jest.fn() },
    passwordResetToken: {
      deleteMany: jest.fn(),
      create: jest.fn(),
      findUnique: jest.fn(),
      update: jest.fn(),
    },
  };
  const jwt = { signAsync: jest.fn().mockResolvedValue('signed-token') };
  const service = new AuthService(
    prisma as unknown as PrismaService,
    jwt as unknown as JwtService,
  );
  const pipe = new ValidationPipe({ whitelist: true, transform: true });

  beforeEach(() => jest.clearAllMocks());
  afterEach(() => jest.restoreAllMocks());

  it('returns a generic message for unknown emails without creating a token', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    const result = await service.forgotPassword({ email: 'Nobody@Waslny.com' });

    expect(result).toEqual({
      message: 'If an account exists for this email, a reset link has been sent.',
    });
    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { email: 'nobody@waslny.com' },
    });
    expect(prisma.passwordResetToken.create).not.toHaveBeenCalled();
  });

  it('directs Google-only accounts to Google sign-in', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'u1',
      googleId: 'google-123',
      passwordHash: null,
    });

    const result = await service.forgotPassword({ email: 'g@waslny.com' });

    expect(result).toEqual({
      message: 'This account uses Google sign-in. Please continue with Google.',
    });
    expect(prisma.passwordResetToken.create).not.toHaveBeenCalled();
  });

  it('invalidates old tokens and creates a 30-minute token', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'u2',
      googleId: null,
      passwordHash: 'old-hash',
    });
    prisma.passwordResetToken.create.mockImplementation(
      async ({ data }: any) => ({ id: 't1', ...data }),
    );
    const before = Date.now();

    const result = await service.forgotPassword({ email: 'u@waslny.com' });

    expect(result).toEqual({
      message: 'If an account exists for this email, a reset link has been sent.',
    });
    expect(prisma.passwordResetToken.deleteMany).toHaveBeenCalledWith({
      where: { userId: 'u2', usedAt: null },
    });
    const data = prisma.passwordResetToken.create.mock.calls[0][0].data;
    expect(data.userId).toBe('u2');
    // Stored value is a SHA-256 hex digest, never the raw link token.
    expect(data.token).toMatch(/^[0-9a-f]{64}$/);
    const ttl = new Date(data.expiresAt).getTime() - before;
    expect(ttl).toBeGreaterThan(29 * 60 * 1000);
    expect(ttl).toBeLessThanOrEqual(30 * 60 * 1000 + 5000);
  });

  it('never writes the reset link or raw token to the console', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'u3',
      googleId: null,
      passwordHash: 'old-hash',
    });
    const logSpy = jest.spyOn(console, 'log').mockImplementation(() => undefined);

    await service.forgotPassword({ email: 'u3@waslny.com' });

    expect(logSpy).not.toHaveBeenCalled();
    const storedHash = prisma.passwordResetToken.create.mock.calls[0][0].data.token;
    expect(logSpy.mock.calls.flat().join(' ')).not.toContain(storedHash);
  });

  it('resets the password and marks the token used', async () => {
    const raw = 'a'.repeat(64);
    const { createHash } = await import('crypto');
    prisma.passwordResetToken.findUnique.mockResolvedValue({
      id: 't1',
      userId: 'u2',
      token: createHash('sha256').update(raw).digest('hex'),
      expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      usedAt: null,
    });
    prisma.user.findUnique.mockResolvedValue({ id: 'u2', suspendedAt: null });

    const result = await service.resetPassword({
      token: raw,
      newPassword: 'NewSecret123',
    });

    expect(result).toEqual({
      message: 'Password has been reset. Please sign in with your new password.',
    });
    const storedHash = prisma.user.update.mock.calls[0][0].data.passwordHash;
    expect(await bcrypt.compare('NewSecret123', storedHash)).toBe(true);
    expect(prisma.passwordResetToken.update).toHaveBeenCalledWith({
      where: { id: 't1' },
      data: { usedAt: expect.any(Date) },
    });
  });

  it('rejects expired tokens', async () => {
    prisma.passwordResetToken.findUnique.mockResolvedValue({
      id: 't1',
      userId: 'u2',
      expiresAt: new Date(Date.now() - 1000),
      usedAt: null,
    });

    await expect(
      service.resetPassword({ token: 'b'.repeat(64), newPassword: 'NewSecret123' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('rejects already-used tokens', async () => {
    prisma.passwordResetToken.findUnique.mockResolvedValue({
      id: 't1',
      userId: 'u2',
      expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      usedAt: new Date(),
    });

    await expect(
      service.resetPassword({ token: 'c'.repeat(64), newPassword: 'NewSecret123' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('rejects unknown tokens', async () => {
    prisma.passwordResetToken.findUnique.mockResolvedValue(null);

    await expect(
      service.resetPassword({ token: 'd'.repeat(64), newPassword: 'NewSecret123' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects reset for suspended accounts', async () => {
    prisma.passwordResetToken.findUnique.mockResolvedValue({
      id: 't1',
      userId: 'u2',
      expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      usedAt: null,
    });
    prisma.user.findUnique.mockResolvedValue({ id: 'u2', suspendedAt: new Date() });

    await expect(
      service.resetPassword({ token: 'e'.repeat(64), newPassword: 'NewSecret123' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('rejects short passwords at the DTO level', async () => {
    await expect(
      pipe.transform(
        { token: 'f'.repeat(64), newPassword: 'short' },
        { type: 'body', metatype: ResetPasswordDto },
      ),
    ).rejects.toBeDefined();
  });
});
