import { Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { OrderEventsModule } from '../order-events/order-events.module';
import { CaptainsModule } from '../captains/captains.module';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';

@Module({ imports: [NotificationsModule, OrderEventsModule, CaptainsModule], controllers: [AdminController], providers: [AdminService] })
export class AdminModule {}