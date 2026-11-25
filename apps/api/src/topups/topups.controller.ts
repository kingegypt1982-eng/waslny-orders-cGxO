import { Body, Controller, Get, Headers, Param, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser, Roles } from '../auth/auth.decorators';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { CreateTopUpDto } from './dto/create-topup.dto';
import { TopUpsService } from './topups.service';

@ApiTags('Wallet top-ups')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Controller('wallet')
export class TopUpsController {
  constructor(private readonly topUps: TopUpsService) {}

  @Post('topups')
  @Roles('CAPTAIN')
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  create(
    @CurrentUser() user: { id: string },
    @Body() body: CreateTopUpDto,
    @Headers('origin') origin?: string,
  ) {
    return this.topUps.createTopUp(user.id, body.amount, origin);
  }

  @Post('topups/:id/development-success')
  @Roles('CAPTAIN')
  simulateDevelopmentSuccess(@CurrentUser() user: { id: string }, @Param('id') id: string) {
    return this.topUps.simulateDevelopmentSuccess(user.id, id);
  }

  @Get('topups')
  @Roles('CAPTAIN')
  list(@CurrentUser() user: { id: string }, @Query('take') take?: string, @Query('skip') skip?: string) {
    return this.topUps.listTopUps(user.id, take ? Number(take) : undefined, skip ? Number(skip) : undefined);
  }

  @Get('topups/:id')
  @Roles('CAPTAIN')
  get(@CurrentUser() user: { id: string }, @Param('id') id: string) {
    return this.topUps.getTopUp(user.id, id);
  }
}
