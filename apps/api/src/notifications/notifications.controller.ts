import { Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/auth.decorators';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { NotificationsService } from './notifications.service';

@ApiTags('Notifications')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get() list(@CurrentUser() user: { id: string }) {
    return this.notifications.list(user.id);
  }

  @Get('unread-count') unreadCount(@CurrentUser() user: { id: string }) {
    return this.notifications.unreadCount(user.id);
  }

  @Post('read-all') readAll(@CurrentUser() user: { id: string }) {
    return this.notifications.markAllRead(user.id);
  }

  @Patch(':id/read') read(@CurrentUser() user: { id: string }, @Param('id') id: string) {
    return this.notifications.markRead(user.id, id);
  }
}
