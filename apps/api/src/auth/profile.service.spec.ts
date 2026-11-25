import { PrismaService } from '../prisma/prisma.service';
import { ProfileService } from './profile.service';

describe('ProfileService', () => {
  const prisma = { user: { update: jest.fn() } };
  const service = new ProfileService(prisma as unknown as PrismaService);

  beforeEach(() => jest.clearAllMocks());

  it('updates the authenticated user name and phone only', async () => {
    prisma.user.update.mockResolvedValue({
      id: 'u1',
      email: 'client@example.com',
      name: 'Updated Client',
      phone: '01000000000',
      role: 'CLIENT',
    });

    const result = await service.update('u1', {
      name: '  Updated Client  ',
      phone: '01000000000',
    });

    expect(prisma.user.update).toHaveBeenCalledWith({
      where: { id: 'u1' },
      data: { name: 'Updated Client', phone: '01000000000' },
      select: { id: true, email: true, name: true, phone: true, role: true },
    });
    expect(result.role).toBe('CLIENT');
  });
});