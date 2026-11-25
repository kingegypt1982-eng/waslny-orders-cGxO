import { Body, Controller, Get, Logger, Param, Patch, Post, StreamableFile, UseGuards } from '@nestjs/common';
import { BadRequestException, ConflictException, ForbiddenException, NotFoundException, UploadedFile, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { IsBoolean, IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';
import { randomUUID } from 'crypto';
import { existsSync, createReadStream } from 'fs';
import { mkdir, writeFile } from 'fs/promises';
import { basename, dirname, join, resolve } from 'path';
import { memoryStorage } from 'multer';
import { PrismaClientKnownRequestError } from '@prisma/client/runtime/library';
import { CurrentUser, Roles } from '../auth/auth.decorators';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.module';
import { NationalIdCryptoService } from './national-id-crypto.service';
import { validateEgyptianNationalId } from './national-id.util';
import { CaptainProfileUpdateDto } from './captain-profile.dto';
import { DEFAULT_MAX_RADIUS_KM, DEFAULT_MIN_RADIUS_KM } from '../orders/orders.constants';
import { toPosixPath } from '../orders/proof-upload';
import { FcmService } from '../firebase/fcm.service';

class LocationDto {
  @IsNumber() @Min(-90) @Max(90) latitude: number;
  @IsNumber() @Min(-180) @Max(180) longitude: number;
}

class AvailabilityDto {
  @IsBoolean() isOnline: boolean;
  @IsOptional() @IsNumber() @Min(1) @Max(100) serviceRadiusKm?: number;
}

class FcmTokenDto {
  @IsString() token: string;
}

@ApiTags('Captains')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('CAPTAIN')
@Controller('captains')
export class CaptainsController {
  private readonly logger = new Logger(CaptainsController.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly crypto: NationalIdCryptoService,
    private readonly fcm: FcmService,
  ) {}

  @Get('me') async profile(@CurrentUser() user: { id: string }) {
    const profile = await this.prisma.captainProfile.findUnique({
      where: { userId: user.id },
      include: { user: { select: { id: true, name: true, email: true, phone: true, wallet: true } } },
    });
    if (!profile) return profile;
    const missing: string[] = [];
    if (!profile.user?.phone?.trim()) missing.push('phone');
    if (!profile.nationalIdHash || !profile.nationalIdLast4) missing.push('nationalId');
    if (!profile.governorate) missing.push('governorate');
    if (!profile.licenseNumber) missing.push('licenseNumber');
    if (!profile.vehicleRegistrationNumber) missing.push('vehicleRegistrationNumber');
    if (!profile.dateOfBirth) missing.push('dateOfBirth');
    if (!profile.vehicleType || !profile.vehiclePlate) missing.push('vehicle');
    if (!profile.vehicleMake || !profile.vehicleColor) missing.push('vehicleDetails');
    if (!profile.profilePhotoDocument || profile.profilePhotoDocument === 'PENDING_UPLOAD') missing.push('profilePhoto');
    // GET routes must not create the settings row as a side effect. Fall back
    // to the schema defaults when the singleton row has never been created.
    const settings = await this.prisma.pricingSettings.findUnique({ where: { id: 'default' } });
    const safe = { ...profile } as Record<string, unknown>;
    delete safe.nationalIdEncrypted;
    delete safe.nationalIdHash;
    return {
      ...safe,
      missing,
      radiusBand: {
        min: Number(settings?.minRadiusKm ?? DEFAULT_MIN_RADIUS_KM),
        max: Number(settings?.maxRadiusKm ?? DEFAULT_MAX_RADIUS_KM),
      },
    };
  }

  @Post('documents/:type')
  @UseInterceptors(FileInterceptor('file', {
    storage: memoryStorage(),
    limits: { fileSize: 8 * 1024 * 1024 },
    fileFilter: (_request, file, callback) => {
      if (!['application/pdf', 'image/jpeg', 'image/png'].includes(file.mimetype)) {
        callback(new BadRequestException('Upload a PDF, JPG, or PNG file'), false);
        return;
      }
      callback(null, true);
    },
  }))
  async uploadDocument(
    @CurrentUser() user: { id: string },
    @Param('type') type: string,
    @UploadedFile() file: Express.Multer.File,
  ) {
    const field = documentFields[type as keyof typeof documentFields];
    if (!field || !file) throw new BadRequestException('Document type and file are required');
    const extension = file.mimetype === 'application/pdf' ? '.pdf' : file.mimetype === 'image/png' ? '.png' : '.jpg';
    const relativePath = toPosixPath(join('captains', user.id, `${randomUUID()}${extension}`));
    const absolutePath = join(process.cwd(), 'uploads', relativePath);
    await mkdir(dirname(absolutePath), { recursive: true });
    await writeFile(absolutePath, file.buffer);
    await this.prisma.captainProfile.update({ where: { userId: user.id }, data: { [field]: relativePath } });
    return { type, uploaded: true };
  }

  @Get('me/documents/:type')
  async myDocument(@CurrentUser() user: { id: string }, @Param('type') type: string) {
    const field = documentFields[type as keyof typeof documentFields];
    if (!field) throw new BadRequestException('Unknown document type');
    const profile = await this.prisma.captainProfile.findUnique({
      where: { userId: user.id },
      select: { [field]: true },
    });
    const storedPath = (profile as Record<string, string> | null)?.[field];
    const normalizedPath = storedPath ? toPosixPath(storedPath) : storedPath;
    if (!normalizedPath || normalizedPath === 'PENDING_UPLOAD' || !normalizedPath.startsWith(`captains/${user.id}/`)) {
      throw new BadRequestException('Document has not been uploaded');
    }
    const root = resolve(process.cwd(), 'uploads');
    const path = resolve(root, normalizedPath);
    if (!path.startsWith(`${root}/`) && !path.startsWith(`${root}\\`)) {
      throw new BadRequestException('Document not found');
    }
    if (!existsSync(path)) throw new BadRequestException('Document file is missing');
    const mimeType = path.endsWith('.pdf') ? 'application/pdf' : path.endsWith('.png') ? 'image/png' : 'image/jpeg';
    return new StreamableFile(createReadStream(path), {
      type: mimeType,
      disposition: `inline; filename="${basename(path)}"`,
    });
  }

  @Patch('me/profile')
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  async updateProfile(@CurrentUser() user: { id: string }, @Body() body: CaptainProfileUpdateDto) {
    const data: any = {};

    if (body.phone !== undefined) {
      data.user = { update: { phone: body.phone } };
    }

    if (body.governorate !== undefined) {
      data.governorate = body.governorate;
    }
    if (body.licenseNumber !== undefined) {
      data.licenseNumber = body.licenseNumber.trim() || null;
    }
    if (body.vehicleRegistrationNumber !== undefined) {
      data.vehicleRegistrationNumber = body.vehicleRegistrationNumber.trim() || null;
    }
    if (body.vehiclePlate !== undefined) {
      data.vehiclePlate = body.vehiclePlate.trim() || null;
    }
    if (body.vehicleMake !== undefined) {
      data.vehicleMake = body.vehicleMake.trim() || null;
    }
    if (body.vehicleModel !== undefined) {
      data.vehicleModel = body.vehicleModel.trim() || null;
    }
    if (body.vehicleColor !== undefined) {
      data.vehicleColor = body.vehicleColor.trim() || null;
    }

    if (body.dateOfBirth !== undefined) {
      const parsed = new Date(body.dateOfBirth);
      if (Number.isNaN(parsed.getTime())) throw new BadRequestException('dateOfBirth must be a valid date');
      data.dateOfBirth = parsed;
    }

    if (body.nationalId !== undefined) {
      const nid = body.nationalId.trim();
      const validation = validateEgyptianNationalId(nid);
      if (!validation.valid) {
        throw new BadRequestException(validation.error || 'Invalid national ID');
      }
      const hash = this.crypto.hash(nid);
      const exists = await this.prisma.captainProfile.findFirst({
        where: {
          nationalIdHash: hash,
          userId: { not: user.id },
        },
        select: { userId: true },
      });
      if (exists) {
        throw new ConflictException({ code: 'NATIONAL_ID_DUPLICATE', message: 'National ID is already registered' });
      }
      data.nationalIdEncrypted = this.crypto.encrypt(nid);
      data.nationalIdHash = hash;
      data.nationalIdLast4 = this.crypto.last4(nid);
      if (body.dateOfBirth === undefined) {
        data.dateOfBirth = new Date(Date.UTC(validation.birthYear!, validation.birthMonth! - 1, validation.birthDay!));
      }
    }

    try {
      const profile = await this.prisma.captainProfile.update({
        where: { userId: user.id },
        data,
        select: {
          id: true,
          userId: true,
          status: true,
          dateOfBirth: true,
          governorate: true,
          licenseNumber: true,
          vehicleRegistrationNumber: true,
          vehiclePlate: true,
          vehicleMake: true,
          vehicleModel: true,
          vehicleColor: true,
          nationalIdLast4: true,
        },
      });
      return profile;
    } catch (err) {
      if (err instanceof PrismaClientKnownRequestError && err.code === 'P2002') {
        throw new ConflictException({ code: 'NATIONAL_ID_DUPLICATE', message: 'National ID is already registered' });
      }
      throw err;
    }
  }

  @Post('location') async location(@CurrentUser() user: { id: string }, @Body() body: LocationDto) {
    const profile = await this.prisma.captainProfile.findUnique({ where: { userId: user.id }, select: { status: true } });
    if (!profile || profile.status !== 'ACTIVE') return { updated: false, reason: 'Captain is not approved' };
    // Keep the heartbeat in PostgreSQL as well: the orders feed filters by it.
    await this.prisma.captainProfile.update({
      where: { userId: user.id },
      data: { lastLat: body.latitude, lastLng: body.longitude, lastSeenAt: new Date() },
    });
    try {
      const updated = await this.redis.updateCaptainLocation(user.id, body.latitude, body.longitude);
      return { updated };
    } catch (error) {
      // Redis only powers nearby-captain search. The PostgreSQL heartbeat is
      // already saved, so a Redis outage must not turn this into a 500.
      const detail = error instanceof Error ? error.message : String(error);
      this.logger.warn(`Redis captain location update failed; PostgreSQL heartbeat saved: ${detail}`);
      return { updated: false, reason: 'Location saved; live index unavailable' };
    }
  }

  /**
   * Online/offline switch for the orders feed plus the captain's own service
   * radius. The radius must stay inside the admin-configured band
   * (PricingSettings.minRadiusKm..maxRadiusKm).
   */
  @Patch('me/availability')
  async availability(@CurrentUser() user: { id: string }, @Body() body: AvailabilityDto) {
    const profile = await this.prisma.captainProfile.findUnique({
      where: { userId: user.id },
      select: { status: true },
    });
    if (!profile) throw new NotFoundException('Captain profile not found');
    if (body.isOnline && profile.status !== 'ACTIVE') {
      throw new ForbiddenException('Captain account is not approved');
    }
    const settings = await this.prisma.pricingSettings.upsert({ where: { id: 'default' }, update: {}, create: {} });
    const min = Number(settings.minRadiusKm);
    const max = Number(settings.maxRadiusKm);
    const data: { isOnline: boolean; serviceRadiusKm?: number } = { isOnline: body.isOnline };
    if (body.serviceRadiusKm !== undefined) {
      if (body.serviceRadiusKm < min || body.serviceRadiusKm > max) {
        throw new BadRequestException({
          code: 'RADIUS_OUT_OF_RANGE',
          message: `Service radius must be between ${min} and ${max} km`,
          min,
          max,
        });
      }
      data.serviceRadiusKm = body.serviceRadiusKm;
    }
    return this.prisma.captainProfile.update({
      where: { userId: user.id },
      data,
      select: { isOnline: true, serviceRadiusKm: true },
    });
  }

  /**
   * Register the captain's FCM token for push notifications.
   * Called when the app starts or token refreshes.
   */
  @Post('me/fcm-token')
  async registerFcmToken(@CurrentUser() user: { id: string }, @Body() body: FcmTokenDto) {
    if (!body.token?.trim()) {
      throw new BadRequestException('FCM token is required');
    }
    await this.fcm.registerFcmToken(user.id, body.token.trim());
    return { registered: true };
  }

  /**
   * Clear the captain's FCM token (e.g., on logout).
   */
  @Post('me/fcm-token/clear')
  async clearFcmToken(@CurrentUser() user: { id: string }) {
    await this.fcm.clearFcmToken(user.id);
    return { cleared: true };
  }

  @Get('wallet') async wallet(@CurrentUser() user: { id: string }) {
    const [wallet, pricing] = await Promise.all([
      this.prisma.wallet.findUnique({
        where: { userId: user.id },
        include: { user: { select: { walletTransactions: { orderBy: { createdAt: 'desc' }, take: 50 } } } },
      }),
      this.prisma.pricingSettings.findUnique({ where: { id: 'default' } }),
    ]);
    return { ...wallet, minimumWalletBalance: pricing?.minimumWalletBalance ?? 0 };
  }
}

const documentFields = {
  identity: 'nationalIdDocument',
  'identity-back': 'nationalIdBackDocument',
  license: 'licenseDocument',
  'license-back': 'licenseBackDocument',
  vehicle: 'vehicleDocument',
  'vehicle-back': 'vehicleBackDocument',
  'profile-photo': 'profilePhotoDocument',
} as const;