import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { AuthController } from './auth.controller';
import { ProfileController } from './profile.controller';
import { AuthService } from './auth.service';
import { ProfileService } from './profile.service';
import { JwtStrategy } from './jwt.strategy';
import { RolesGuard } from './roles.guard';

@Module({
  imports: [
    PassportModule,
    JwtModule.registerAsync({
      // No fallback: resolved after ConfigModule loads .env, and main.ts
      // refuses to boot when JWT_SECRET is missing.
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.getOrThrow<string>('JWT_SECRET'),
        signOptions: { expiresIn: config.get<string>('JWT_EXPIRES_IN') ?? '7d' },
      }),
    }),
  ],
  controllers: [AuthController, ProfileController],
  providers: [AuthService, ProfileService, JwtStrategy, RolesGuard],
  exports: [JwtModule, RolesGuard],
})
export class AuthModule {}