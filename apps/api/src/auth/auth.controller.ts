import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import { CurrentUser } from './auth.decorators';
import { JwtAuthGuard } from './jwt-auth.guard';
import { ForgotPasswordDto } from './dto/forgot-password.dto';
import { GoogleLoginDto } from './dto/google-login.dto';
import { LoginDto } from './dto/login.dto';
import { RegisterDto } from './dto/register.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { SetPasswordDto } from './dto/set-password.dto';

@ApiTags('Authentication')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}
  // Stricter than the global limit: brute-force protection on credentials endpoints.
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('register') register(@Body() body: RegisterDto) { return this.auth.register(body); }
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('login') login(@Body() body: LoginDto) { return this.auth.login(body); }
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('google') google(@Body() body: GoogleLoginDto) { return this.auth.googleLogin(body); }
  // Public on purpose: the Flutter web client must render the Google button
  // with the same client ID the API verifies as the token audience. A web
  // OAuth client ID is not a secret (it is visible in every browser request).
  @Get('google/config') googleConfig() {
    return { clientId: process.env.GOOGLE_CLIENT_ID ?? '' };
  }
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('forgot-password') forgotPassword(@Body() body: ForgotPasswordDto) { return this.auth.forgotPassword(body); }
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('reset-password') resetPassword(@Body() body: ResetPasswordDto) { return this.auth.resetPassword(body); }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Get('password-status')
  passwordStatus(@CurrentUser() user: { id: string }) {
    return this.auth.passwordStatus(user.id);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('set-password')
  setPassword(@CurrentUser() user: { id: string }, @Body() body: SetPasswordDto) {
    return this.auth.setPassword(user.id, body);
  }
}