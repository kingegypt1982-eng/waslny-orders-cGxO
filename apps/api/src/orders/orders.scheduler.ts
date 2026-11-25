import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { OrdersService } from './orders.service';

/**
 * Drives OrdersService.expireStaleSearches() every 60 seconds so orders that
 * nobody accepted are cancelled by the server, not by the client app.
 * Overlap guard: a slow cycle skips instead of stacking (single instance;
 * multi-instance deployments would need a distributed lock instead).
 */
@Injectable()
export class OrdersScheduler {
  private readonly logger = new Logger(OrdersScheduler.name);
  private running = false;

  constructor(private readonly orders: OrdersService) {}

  @Cron(CronExpression.EVERY_MINUTE)
  async expireSearches() {
    if (this.running) return;
    this.running = true;
    try {
      const result = await this.orders.expireStaleSearches();
      if (result.expired > 0) {
        this.logger.log(`expired order searches: checked=${result.checked} cancelled=${result.expired}`);
      }
    } catch {
      // Static text only: error details could echo request internals.
      this.logger.error('order expiry cycle failed');
    } finally {
      this.running = false;
    }
  }
}
