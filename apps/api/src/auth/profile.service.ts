import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ProfileUpdateDto } from './dto/profile-update.dto';

@Injectable()
export class ProfileService {
  constructor(private readonly prisma: PrismaService) {}

  update(userId: string, input: ProfileUpdateDto) {
    return this.prisma.user.update({
      where: { id: userId },
      data: {
        name: input.name.trim(),
        ...(input.phone !== undefined ? { phone: input.phone?.trim() || null } : {}),
      },
      select: { id: true, email: true, name: true, phone: true, role: true },
    });
  }
}