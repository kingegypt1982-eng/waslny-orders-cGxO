import { BadRequestException, ConflictException, Injectable, InternalServerErrorException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { OAuth2Client, TokenPayload } from 'google-auth-library';
import * as bcrypt from 'bcrypt';
import { createHash, randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { ForgotPasswordDto } from './dto/forgot-password.dto';
import { GoogleLoginDto } from './dto/google-login.dto';
import { LoginDto } from './dto/login.dto';
import { RegisterDto } from './dto/register.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { SetPasswordDto } from './dto/set-password.dto';

export interface GoogleProfile {
  sub: string;
  email: string;
  name: string;
}

@Injectable()
export class AuthService {
  constructor(private readonly prisma: PrismaService, private readonly jwt: JwtService) {}

  async register(input: RegisterDto) {
    if (input.role === 'CAPTAIN' && (!input.vehicleType || !input.vehiclePlate)) {
      throw new ConflictException('Captain vehicle details are required');
    }
    if (await this.prisma.user.findUnique({ where: { email: input.email.toLowerCase() } })) {
      throw new ConflictException('Email is already registered');
    }
    const user = await this.prisma.user.create({
      data: {
        email: input.email.toLowerCase(), name: input.name, phone: input.phone,
        passwordHash: await bcrypt.hash(input.password, 12), role: input.role,
        wallet: { create: {} },
        ...(input.role === 'CAPTAIN' ? {
          captain: { create: {
            nationalIdDocument: input.nationalIdDocument ?? 'PENDING_UPLOAD',
            licenseDocument: input.licenseDocument ?? 'PENDING_UPLOAD',
            vehicleDocument: input.vehicleDocument ?? 'PENDING_UPLOAD',
            vehicleType: input.vehicleType!, vehiclePlate: input.vehiclePlate!,
          } },
        } : {}),
      },
      select: { id: true, email: true, name: true, role: true },
    });
    return this.session(user);
  }

  async login(input: LoginDto) {
    const user = await this.prisma.user.findUnique({ where: { email: input.email.toLowerCase() } });
    // Passwordless (Google) accounts have no passwordHash: same generic error, no crash.
    if (!user || user.suspendedAt || !user.passwordHash || !(await bcrypt.compare(input.password, user.passwordHash))) {
      throw new UnauthorizedException('Invalid email or password');
    }
    return this.session({ id: user.id, email: user.email, name: user.name, role: user.role });
  }

  /** Verifies a Google ID token. Overridable in tests to avoid calling Google. */
  async verifyGoogleToken(idToken: string): Promise<GoogleProfile> {
    const clientId = process.env.GOOGLE_CLIENT_ID;
    if (!clientId) {
      throw new InternalServerErrorException('Google sign-in is not configured (GOOGLE_CLIENT_ID is empty)');
    }
    let payload: TokenPayload | undefined;
    try {
      const ticket = await new OAuth2Client(clientId).verifyIdToken({ idToken, audience: clientId });
      payload = ticket.getPayload();
    } catch {
      payload = undefined;
    }
    if (!payload?.sub || !payload.email || payload.email_verified !== true) {
      throw new UnauthorizedException('Invalid Google credential');
    }
    return { sub: payload.sub, email: payload.email, name: payload.name ?? payload.email };
  }

  async googleLogin(input: GoogleLoginDto) {
    const google = await this.verifyGoogleToken(input.idToken);
    const email = google.email.toLowerCase();
    const existing = await this.prisma.user.findUnique({ where: { email } });
    if (existing?.suspendedAt) {
      throw new UnauthorizedException('Invalid email or password');
    }
    let account: { id: string; email: string; name: string; role: string };
    if (existing) {
      if (existing.googleId && existing.googleId !== google.sub) {
        throw new ConflictException({ code: 'GOOGLE_ACCOUNT_MISMATCH', message: 'This email is already linked to another Google account' });
      }
      // Never attach a Google identity to an account that already has its own
      // credentials. Registration does not verify email ownership, so an
      // attacker can pre-register the victim's email and keep the password
      // after the victim "links" Google (pre-hijacking). The token is already
      // verified here, so this message does not leak account existence to
      // anonymous callers.
      if (!existing.googleId && existing.passwordHash) {
        throw new ConflictException({
          code: 'EMAIL_USES_PASSWORD_LOGIN',
          message: 'This email is registered with a password. Sign in with your password to continue',
        });
      }
      // No Google ID and no password: the account has no other way in, so
      // linking it is safe (nothing for an attacker to keep using).
      account = existing.googleId
        ? { id: existing.id, email: existing.email, name: existing.name, role: existing.role }
        : await this.prisma.user.update({
            where: { id: existing.id },
            data: { googleId: google.sub },
            select: { id: true, email: true, name: true, role: true },
          });
    } else {
      if (!input.termsAccepted) {
        throw new BadRequestException({
          code: 'TERMS_REQUIRED',
          message: 'Accept the terms and conditions to create a Google account',
        });
      }
      // No phone yet (completed later); captain vehicle stays NULL until completed.
      account = await this.prisma.user.create({
        data: {
          email, name: google.name, phone: null, passwordHash: null, googleId: google.sub, role: input.role,
          wallet: { create: {} },
          ...(input.role === 'CAPTAIN' ? {
            captain: { create: {
              nationalIdDocument: 'PENDING_UPLOAD',
              licenseDocument: 'PENDING_UPLOAD',
              vehicleDocument: 'PENDING_UPLOAD',
              vehicleType: input.vehicleType ?? null,
              vehiclePlate: input.vehiclePlate ?? null,
            } },
          } : {}),
        },
        select: { id: true, email: true, name: true, role: true },
      });
    }
    const missing = await this.profileMissing(account.id, account.role);
    return { ...(await this.session(account)), missing };
  }

  private async profileMissing(userId: string, role: string): Promise<string[]> {
    const missing: string[] = [];
    const profile = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { phone: true, captain: { select: { vehicleType: true, vehiclePlate: true } } },
    });
    if (!profile?.phone?.trim()) missing.push('phone');
    if (role === 'CAPTAIN' && (!profile?.captain?.vehicleType || !profile?.captain?.vehiclePlate)) {
      missing.push('vehicle');
    }
    return missing;
  }

  private async session(user: { id: string; email: string; name: string; role: string }) {
    return { accessToken: await this.jwt.signAsync({ sub: user.id, role: user.role }), user };
  }

  /** Link-based password reset (no OTP). Raw token is only ever sent in the
   * reset link; only its SHA-256 hash is persisted. */
  async forgotPassword(input: ForgotPasswordDto) {
    const email = input.email.toLowerCase();
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user) {
      return { message: 'If an account exists for this email, a reset link has been sent.' };
    }
    if (user.googleId && !user.passwordHash) {
      return { message: 'This account uses Google sign-in. Please continue with Google.' };
    }
    await this.prisma.passwordResetToken.deleteMany({
      where: { userId: user.id, usedAt: null },
    });
    const raw = randomBytes(32).toString('hex');
    const token = createHash('sha256').update(raw).digest('hex');
    await this.prisma.passwordResetToken.create({
      data: {
        userId: user.id,
        token,
        expiresAt: new Date(Date.now() + 30 * 60 * 1000),
      },
    });
    // TODO(prod): deliver the reset link through an email provider. The raw
    // token is deliberately never logged: logs are accessible to anyone with
    // operational access and would allow account takeover.
    return { message: 'If an account exists for this email, a reset link has been sent.' };
  }

  async resetPassword(input: ResetPasswordDto) {
    const token = createHash('sha256').update(input.token).digest('hex');
    const row = await this.prisma.passwordResetToken.findUnique({ where: { token } });
    if (!row || row.usedAt || row.expiresAt.getTime() < Date.now()) {
      throw new UnauthorizedException('Invalid or expired reset token');
    }
    const user = await this.prisma.user.findUnique({ where: { id: row.userId } });
    if (!user || user.suspendedAt) {
      throw new UnauthorizedException('Invalid or expired reset token');
    }
    await this.prisma.user.update({
      where: { id: user.id },
      data: { passwordHash: await bcrypt.hash(input.newPassword, 12) },
    });
    await this.prisma.passwordResetToken.update({
      where: { id: row.id },
      data: { usedAt: new Date() },
    });
    return { message: 'Password has been reset. Please sign in with your new password.' };
  }

  /** Whether the signed-in account already has a password. Used by the mobile
   * profile screen to choose between "set password" and "change password". */
  async passwordStatus(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { passwordHash: true },
    });
    if (!user) throw new UnauthorizedException('Invalid or expired session');
    return { hasPassword: Boolean(user.passwordHash) };
  }

  /** Sets a password on a passwordless (Google-created) account, or changes an
   * existing one after verifying the current password. The JWT guard on the
   * controller proves ownership of the account; a verified Google token was
   * already required to create a passwordless account. */
  async setPassword(userId: string, input: SetPasswordDto) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user || user.suspendedAt) {
      throw new UnauthorizedException('Invalid or expired session');
    }
    if (user.passwordHash) {
      if (!input.currentPassword) {
        throw new BadRequestException({
          code: 'CURRENT_PASSWORD_REQUIRED',
          message: 'Current password is required',
        });
      }
      if (!(await bcrypt.compare(input.currentPassword, user.passwordHash))) {
        throw new BadRequestException({
          code: 'INVALID_CURRENT_PASSWORD',
          message: 'Current password is incorrect',
        });
      }
    }
    await this.prisma.user.update({
      where: { id: userId },
      data: { passwordHash: await bcrypt.hash(input.newPassword, 12) },
    });
    return {
      message: user.passwordHash
        ? 'Password changed. Use your new password next time you sign in.'
        : 'Password added. You can now sign in with your email and password.',
    };
  }
}
