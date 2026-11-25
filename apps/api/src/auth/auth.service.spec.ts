import { ConflictException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { PrismaService } from '../prisma/prisma.service';

describe('AuthService', () => {
  const prisma = { user: { findUnique: jest.fn(), create: jest.fn() } };
  const jwt = { signAsync: jest.fn().mockResolvedValue('signed-token') };
  const service = new AuthService(
    prisma as unknown as PrismaService,
    jwt as unknown as JwtService,
  );

  beforeEach(() => jest.clearAllMocks());

  it('registers a client with a hashed password and returns a session', async () => {
    prisma.user.findUnique.mockResolvedValue(null);
    prisma.user.create.mockImplementation(async ({ data }: any) => ({
      id: 'u1',
      email: data.email,
      name: data.name,
      role: data.role,
    }));

    const result = await service.register({
      email: 'Client@Waslny.com',
      password: 'Secret123',
      name: 'Test Client',
      phone: '01000000000',
      role: 'CLIENT',
    });

    expect(prisma.user.findUnique).toHaveBeenCalledWith({ where: { email: 'client@waslny.com' } });
    expect(result.accessToken).toBe('signed-token');
    expect(result.user.email).toBe('client@waslny.com');
    const storedHash = prisma.user.create.mock.calls[0][0].data.passwordHash as string;
    expect(storedHash).not.toBe('Secret123');
    expect(await bcrypt.compare('Secret123', storedHash)).toBe(true);
  });

  it('rejects duplicate emails on register', async () => {
    prisma.user.findUnique.mockResolvedValue({ id: 'existing' });
    await expect(
      service.register({ email: 'dup@waslny.com', password: 'Secret123', name: 'Dup', phone: '01000000000', role: 'CLIENT' }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('requires vehicle details for captain registration', async () => {
    await expect(
      service.register({ email: 'cap@waslny.com', password: 'Secret123', name: 'Cap', phone: '01000000000', role: 'CAPTAIN' }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('logs in with email + password', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'u2',
      email: 'client@waslny.com',
      name: 'Test Client',
      role: 'CLIENT',
      suspendedAt: null,
      passwordHash: await bcrypt.hash('Secret123', 4),
    });

    const result = await service.login({ email: 'CLIENT@waslny.com', password: 'Secret123' });
    expect(result.accessToken).toBe('signed-token');
    expect(result.user.role).toBe('CLIENT');
  });

  it.each(['CAPTAIN', 'ADMIN'] as const)(
    'logs in with email + password for %s accounts',
    async (role) => {
      const email = `${role.toLowerCase()}@waslny.com`;
      prisma.user.findUnique.mockResolvedValue({
        id: `${role.toLowerCase()}-1`,
        email,
        name: `${role} User`,
        role,
        suspendedAt: null,
        passwordHash: await bcrypt.hash('RoleLogin123', 4),
      });

      const result = await service.login({ email, password: 'RoleLogin123' });

      expect(result.user.role).toBe(role);
      expect(result.accessToken).toBe('signed-token');
      expect(jwt.signAsync).toHaveBeenCalledWith({
        sub: `${role.toLowerCase()}-1`,
        role,
      });
    },
  );

  it('rejects wrong passwords and suspended accounts', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'u2',
      email: 'client@waslny.com',
      passwordHash: await bcrypt.hash('Secret123', 4),
      suspendedAt: null,
    });
    await expect(service.login({ email: 'client@waslny.com', password: 'WrongPass1' })).rejects.toBeInstanceOf(
      UnauthorizedException,
    );

    prisma.user.findUnique.mockResolvedValue({
      id: 'u3',
      email: 'banned@waslny.com',
      passwordHash: await bcrypt.hash('Secret123', 4),
      suspendedAt: new Date(),
    });
    await expect(service.login({ email: 'banned@waslny.com', password: 'Secret123' })).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });
});
