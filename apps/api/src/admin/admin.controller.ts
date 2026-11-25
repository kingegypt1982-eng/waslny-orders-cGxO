import { Body, Controller, Get, Param, Patch, Post, Query, StreamableFile, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CaptainStatus } from '@prisma/client';
import { createReadStream } from 'fs';
import { basename } from 'path';
import { IsBoolean } from 'class-validator';
import { CurrentUser, Roles } from '../auth/auth.decorators';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { AdminOrderDto } from './dto/admin-order.dto';
import { AdminCaptainsQueryDto } from './dto/admin-captains-query.dto';
import { AdminCaptainRejectDto } from './dto/admin-captain-reject.dto';
import { AdminOrdersQueryDto } from './dto/admin-orders-query.dto';
import { AdminTransactionsQueryDto } from './dto/admin-transactions-query.dto';
import { UpdatePricingDto } from './dto/update-pricing.dto';
import { AdminTopUpsQueryDto } from '../topups/dto/admin-topups-query.dto';
import { AdminAcknowledgementsQueryDto } from './dto/admin-acknowledgements-query.dto';
import { AdminService } from './admin.service';

class SuspendDto { @IsBoolean() suspended: boolean; }

@ApiTags('Admin')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('ADMIN')
@Controller('admin')
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  @Get('dashboard') dashboard() { return this.admin.dashboard(); }
  @Get('orders') orders(@Query() query: AdminOrdersQueryDto) { return this.admin.orders(query); }
  @Get('orders/:id/events') orderEvents(@Param('id') id: string) { return this.admin.getOrderEvents(id); }
  @Get('orders/:id/proofs') orderProofs(@Param('id') id: string) { return this.admin.orderProofs(id); }
  @Get('orders/:id/invoice') orderInvoice(@Param('id') id: string) { return this.admin.orderInvoice(id); }
  @Get('orders/:id/invoice/photo')
  async orderInvoicePhoto(@Param('id') id: string) {
    const file = await this.admin.orderInvoicePhoto(id);
    return new StreamableFile(createReadStream(file.path), {
      type: file.mimeType,
      disposition: `inline; filename="${basename(file.path)}"`,
    });
  }
  @Get('orders/:id/chat') orderChat(@Param('id') id: string) { return this.admin.getOrderChat(id); }
  @Get('acknowledgements') acknowledgements(@Query() query: AdminAcknowledgementsQueryDto) { return this.admin.acknowledgements(query); }
  @Patch('orders/:id') updateOrder(@Param('id') id: string, @Body() body: AdminOrderDto, @CurrentUser() user: { id: string }) {
    return this.admin.updateOrder(id, body, user.id);
  }
  @Get('captains') captains(@Query() query: AdminCaptainsQueryDto) { return this.admin.captains(query); }
  @Get('captains/:userId') captain(@Param('userId') userId: string) { return this.admin.captain(userId); }
  @Get('captains/:userId/documents/:type')
  async captainDocument(@Param('userId') userId: string, @Param('type') type: string) {
    const file = await this.admin.captainDocument(userId, type);
    return new StreamableFile(createReadStream(file.path), {
      type: file.mimeType,
      disposition: `inline; filename="${basename(file.path)}"`,
    });
  }
  @Post('captains/:userId/approve') approve(@Param('userId') id: string) { return this.admin.reviewCaptain(id, CaptainStatus.ACTIVE); }
  @Post('captains/:userId/reject') reject(@Param('userId') id: string, @Body() body: AdminCaptainRejectDto) { return this.admin.reviewCaptain(id, CaptainStatus.REJECTED, body.reason); }
  @Post('captains/:userId/suspend') suspendCaptain(@Param('userId') id: string) { return this.admin.reviewCaptain(id, CaptainStatus.SUSPENDED); }
  @Post('captains/:userId/unsuspend') unsuspendCaptain(@Param('userId') id: string) { return this.admin.reviewCaptain(id, CaptainStatus.ACTIVE); }
  @Get('clients') clients() { return this.admin.clients(); }
  @Get('wallets') wallets() { return this.admin.wallets(); }
  @Get('transactions') transactions(@Query() query: AdminTransactionsQueryDto) { return this.admin.transactions(query); }
  @Get('topups') topUps(@Query() query: AdminTopUpsQueryDto) { return this.admin.topUps(query); }
  @Patch('users/:userId/suspension') suspendUser(@Param('userId') id: string, @Body() body: SuspendDto) { return this.admin.suspendUser(id, body.suspended); }
  @Get('pricing') pricing() { return this.admin.pricing(); }
  @Patch('pricing') savePricing(@Body() body: UpdatePricingDto) { return this.admin.savePricing(body); }
}