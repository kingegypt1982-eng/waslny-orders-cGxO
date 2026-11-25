import { BadRequestException, UnauthorizedException, ValidationPipe } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { SetPasswordDto } from './dto/set-password.dto';
import { PrismaService } from '../prisma/prisma.service';

describe('Set / change password', () => {
  const prisma = {
    user: { findUnique: jest.fn(), update: jest.fn() },
  };
  const jwt = { signAsync: jest.fn().mockResolvedValue('signed-token') };
  const service = new AuthService(
    prisma as unknown as PrismaService,
    jwt as unknown as JwtService,
  );
  const pipe = new ValidationPipe({ whitelist: true, transform: true });

  beforeEach(() => jest.clearAllMocks());

  it('reports a passwordless Google account', async () => {
    prisma.user.findUnique.mockResolvedValue({
      passwordHash: null,
    });

    await expect(service.passwordStatus('u1')).resolves.toEqual({
      hasPassword: false,
    });
  });

  it('reports an account that already has a password', async () => {
    prisma.user.findUnique.mockResolvedValue({
      passwordHash: await bcrypt.hash('OldSecret1', 4),
    });

    await expect(service.passwordStatus('u1')).resolves.toEqual({
      hasPassword: true,
    });
  });

  it('rejects an unknown account', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(service.passwordStatus('u1')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('adds a password to a Google-only account without a current password', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'u1',
      suspendedAt: null,
      passwordHash: null,
    });

    const result = await service.setPassword('u1', {
      newPassword: 'NewSecret123',
    });

    expect(result.message).toContain('Password added');
    const update = prisma.user.update.mock.calls[0][0];
    expect(update.where).toEqual({ id: 'u1' });
    expect(await bcrypt.compare('NewSecret123', update.data.passwordHash)).toBe(
      true,
    );
  });

  it('requires the current password when one already exists', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'u1',
      suspendedAt: null,
      passwordHash: await bcrypt.hash('OldSecret1', 4),
    });

    const error = await service
      .setPassword('u1', { newPassword: 'NewSecret123' })
      .catch((e) => e);

    expect(error).toBeInstanceOf(BadRequestException);
    expect(error.getResponse()).toMatchObject({
      code: 'CURRENT_PASSWORD_REQUIRED',
    });
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('rejects a wrong current password', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'u1',
      suspendedAt: null,
      passwordHash: await bcrypt.hash('OldSecret1', 4),
    });

    const error = await service
      .setPassword('u1', {
        currentPassword: 'WrongSecret1',
        newPassword: 'NewSecret123',
      })
      .catch((e) => e);

    expect(error).toBeInstanceOf(BadRequestException);
    expect(error.getResponse()).toMatchObject({
      code: 'INVALID_CURRENT_PASSWORD',
    });
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('changes the password after verifying the current one', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'u1',
      suspendedAt: null,
      passwordHash: await bcrypt.hash('OldSecret1', 4),
    });

    const result = await service.setPassword('u1', {
      currentPassword: 'OldSecret1',
      newPassword: 'NewSecret123',
    });

    expect(result.message).toContain('Password changed');
    const update = prisma.user.update.mock.calls[0][0];
    expect(await bcrypt.compare('NewSecret123', update.data.passwordHash)).toBe(
      true,
    );
  });

  it('refuses suspended accounts', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'u1',
      suspendedAt: new Date(),
      passwordHash: null,
    });

    await expect(
      service.setPassword('u1', { newPassword: 'NewSecret123' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('validates the new password length', async () => {
    await expect(
      pipe.transform({ newPassword: 'short' }, { type: 'body', metatype: SetPasswordDto }),
    ).rejects.toBeDefined();
  });
});
