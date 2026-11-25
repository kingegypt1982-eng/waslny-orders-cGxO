import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { ChatService } from './chat.service';

/**
 * Drives ChatService.cleanupOldChats() daily at 3 AM to remove closed chats
 * older than CHAT_CLEANUP_DAYS (default 7 days).
 */
@Injectable()
export class ChatScheduler {
  private readonly logger = new Logger(ChatScheduler.name);
  private running = false;

  constructor(private readonly chat: ChatService) {}

  @Cron('0 3 * * *') // Daily at 3 AM
  async cleanupChats() {
    if (this.running) return;
    this.running = true;
    try {
      const result = await this.chat.cleanupOldChats();
      if (result.deleted > 0) {
        this.logger.log(`chat cleanup: checked=${result.checked} deleted=${result.deleted}`);
      }
    } catch {
      this.logger.error('chat cleanup cycle failed');
    } finally {
      this.running = false;
    }
  }
}