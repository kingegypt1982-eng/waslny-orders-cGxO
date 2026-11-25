import { Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { OrderEventsModule } from '../order-events/order-events.module';
import { PoliciesModule } from '../policies/policies.module';
import { OrdersController } from './orders.controller';
import { OrdersScheduler } from './orders.scheduler';
import { OrdersService } from './orders.service';

@Module({ imports: [NotificationsModule, OrderEventsModule, PoliciesModule], controllers: [OrdersController], providers: [OrdersService, OrdersScheduler], exports: [OrdersService] })
export class OrdersModule {}
