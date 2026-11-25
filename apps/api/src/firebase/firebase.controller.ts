import { Controller, Post, Get, Body, Req, UseGuards, HttpCode, HttpStatus } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { ThrottlerGuard } from '@nestjs/throttler';
import { FirebaseService } from './firebase.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ConfigService } from '@nestjs/config';

@ApiTags('Firebase')
@Controller('firebase')
@UseGuards(ThrottlerGuard)
export class FirebaseController {
  constructor(
    private readonly firebase: FirebaseService,
    private readonly config: ConfigService,
  ) {}

  private isChatEnabled(): boolean {
    return this.config.get<boolean>('CHAT_ENABLED') ?? false;
  }

  @Post('token')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Generate a Firebase Custom Token for the authenticated user' })
  @ApiResponse({ status: 200, description: 'Custom token generated successfully' })
  @ApiResponse({ status: 403, description: 'Chat feature is disabled' })
  @HttpCode(HttpStatus.OK)
  async createCustomToken(@Req() req: { user: { sub: string; role: string } }) {
    if (!this.isChatEnabled()) {
      return { error: 'Chat feature is currently disabled', code: 'CHAT_DISABLED' };
    }

    if (!this.firebase.isInitialized()) {
      return { error: 'Firebase is not configured on the server', code: 'FIREBASE_NOT_CONFIGURED' };
    }

    const uid = req.user.sub;
    const claims = { role: req.user.role };

    try {
      const customToken = await this.firebase.createCustomToken(uid, claims);
      return { customToken };
    } catch (error) {
      return { error: 'Failed to generate custom token', code: 'TOKEN_GENERATION_FAILED' };
    }
  }

  @Get('health')
  @ApiOperation({ summary: 'Check Firebase configuration status' })
  @ApiResponse({ status: 200, description: 'Firebase status' })
  health() {
    return {
      initialized: this.firebase.isInitialized(),
      chatEnabled: this.isChatEnabled(),
    };
  }
}