import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { TopUpsService } from './topups.service';

/**
 * Drives TopUpsService.reconcilePendingBatch() every 60 seconds.
 * Overlap guard: a slow cycle skips instead of stacking (single instance;
 * multi-instance deployments would need a distributed lock instead).
 */
@Injectable()
export class TopupsScheduler {
  private readonly logger = new Logger(TopupsScheduler.name);
  private running = false;

  constructor(private readonly topUps: TopUpsService) {}

  @Cron(CronExpression.EVERY_MINUTE)
  async reconcile() {
    if (this.running) return;
    this.running = true;
    try {
      const result = await this.topUps.reconcilePendingBatch();
      if (result.checked > 0) {
        this.logger.log(`topup reconciliation checked=${result.checked} charged=${result.charged}`);
      }
    } catch {
      // Static text only: error details could echo request internals.
      this.logger.error('topup reconciliation cycle failed');
    } finally {
      this.running = false;
    }
  }
}
