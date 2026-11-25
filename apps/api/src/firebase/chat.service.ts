import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { OrderStatus } from '@prisma/client';
import { Database } from 'firebase-admin/database';
import { FirebaseService } from './firebase.service';

export interface ChatMeta {
  orderId: string;
  clientId: string;
  captainId: string;
  status: 'ACTIVE' | 'CLOSED';
  createdAt: number;
  closedAt?: number;
  closeReason?: 'COMPLETED' | 'CANCELLED' | 'REASSIGNED' | 'EXPIRED';
}

@Injectable()
export class ChatService implements OnModuleInit {
  private readonly logger = new Logger(ChatService.name);
  private database: Database | null = null;
  private readonly cleanupDays: number;
  private readonly enabled: boolean;

  constructor(
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
    private readonly firebase: FirebaseService,
  ) {
    this.cleanupDays = this.config.get<number>('CHAT_CLEANUP_DAYS') ?? 7;
    this.enabled = this.config.get<boolean>('CHAT_ENABLED') ?? false;
  }

  onModuleInit() {
    if (!this.enabled) return;
    this.database = this.firebase.getDatabase();
  }

  private getChatsRef() {
    if (!this.database) {
      throw new Error('Firebase Database not initialized');
    }
    return this.database.ref('chats');
  }

  private getMetaRef(orderId: string) {
    return this.getChatsRef().child('meta').child(orderId);
  }

  private getMessagesRef(orderId: string) {
    return this.getChatsRef().child('messages').child(orderId);
  }

  /**
   * Create a new chat room when a captain accepts an order.
   * Called from OrdersService.accept()
   */
  async createChatForOrder(orderId: string): Promise<void> {
    if (!this.enabled) return;
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: { clientId: true, captainId: true, status: true },
    });

    if (!order || !order.captainId) {
      this.logger.warn(`Cannot create chat: order ${orderId} not found or not assigned`);
      return;
    }

    if (order.status !== OrderStatus.ACCEPTED) {
      this.logger.warn(`Cannot create chat: order ${orderId} is not in ACCEPTED status`);
      return;
    }

    const meta: ChatMeta = {
      orderId,
      clientId: order.clientId,
      captainId: order.captainId,
      status: 'ACTIVE',
      createdAt: Date.now(),
    };

    try {
      await this.getMetaRef(orderId).set(meta);
      this.logger.log(`Chat created for order ${orderId}`);
    } catch (error) {
      this.logger.error(`Failed to create chat for order ${orderId}`, error);
    }
  }

  /**
   * Close a chat room when order is completed, cancelled, or reassigned.
   * Called from OrdersService.complete(), OrdersService.cancel(), OrdersService.release()
   */
  async closeChatForOrder(
    orderId: string,
    reason: 'COMPLETED' | 'CANCELLED' | 'REASSIGNED',
  ): Promise<void> {
    if (!this.enabled) return;
    const metaRef = this.getMetaRef(orderId);
    const snapshot = await metaRef.once('value');

    if (!snapshot.exists()) {
      this.logger.warn(`No chat meta found for order ${orderId}`);
      return;
    }

    const currentMeta = snapshot.val() as ChatMeta;
    if (currentMeta.status === 'CLOSED') {
      this.logger.log(`Chat for order ${orderId} already closed`);
      return;
    }

    const updatedMeta: ChatMeta = {
      ...currentMeta,
      status: 'CLOSED',
      closedAt: Date.now(),
      closeReason: reason,
    };

    try {
      await metaRef.set(updatedMeta);
      this.logger.log(`Chat closed for order ${orderId}, reason: ${reason}`);
    } catch (error) {
      this.logger.error(`Failed to close chat for order ${orderId}`, error);
    }
  }

  /**
   * Reassign a chat to a new captain (when captain releases and new one accepts)
   */
  async reassignChat(orderId: string, newCaptainId: string): Promise<void> {
    if (!this.enabled) return;
    const metaRef = this.getMetaRef(orderId);
    const snapshot = await metaRef.once('value');

    if (!snapshot.exists()) {
      this.logger.warn(`No chat meta found for order ${orderId} to reassign`);
      return;
    }

    const currentMeta = snapshot.val() as ChatMeta;
    if (currentMeta.status === 'CLOSED') {
      this.logger.warn(`Cannot reassign: chat for order ${orderId} is closed`);
      return;
    }

    const updatedMeta: ChatMeta = {
      ...currentMeta,
      captainId: newCaptainId,
    };

    try {
      await metaRef.set(updatedMeta);
      this.logger.log(`Chat reassigned for order ${orderId} to captain ${newCaptainId}`);
    } catch (error) {
      this.logger.error(`Failed to reassign chat for order ${orderId}`, error);
    }
  }

  /**
   * Get chat metadata for an order (used by admin endpoint)
   */
  async getChatMeta(orderId: string): Promise<ChatMeta | null> {
    if (!this.enabled) return null;
    const snapshot = await this.getMetaRef(orderId).once('value');
    if (!snapshot.exists()) return null;
    return snapshot.val() as ChatMeta;
  }

  /**
   * Get messages for an order (used by admin endpoint)
   */
  async getChatMessages(orderId: string, limit: number = 100): Promise<Array<{ senderId: string; content: string; type: string; createdAt: number }>> {
    if (!this.enabled) return [];
    const snapshot = await this.getMessagesRef(orderId)
      .orderByChild('createdAt')
      .limitToLast(limit)
      .once('value');

    if (!snapshot.exists()) return [];

    const messages: Array<{ senderId: string; content: string; type: string; createdAt: number }> = [];
    snapshot.forEach((child) => {
      const val = child.val();
      messages.push({
        senderId: val.senderId,
        content: val.content,
        type: val.type,
        createdAt: val.createdAt,
      });
    });
    return messages;
  }

  /**
   * Cron job: Clean up old closed chats (older than CHAT_CLEANUP_DAYS)
   * Runs daily at 3 AM
   */
  async cleanupOldChats(): Promise<{ checked: number; deleted: number }> {
    if (!this.enabled || !this.database) {
      return { checked: 0, deleted: 0 };
    }

    const cutoff = Date.now() - this.cleanupDays * 24 * 60 * 60 * 1000;
    const metaRef = this.getChatsRef().child('meta');

    const snapshot = await metaRef
      .orderByChild('closedAt')
      .endAt(cutoff)
      .once('value');

    if (!snapshot.exists()) {
      this.logger.log('No old chats to clean up');
      return { checked: 0, deleted: 0 };
    }

    let deleted = 0;
    const toDelete: string[] = [];

    snapshot.forEach((child) => {
      const meta = child.val() as ChatMeta;
      if (meta.status === 'CLOSED' && meta.closedAt && meta.closedAt < cutoff) {
        toDelete.push(child.key!);
      }
    });

    for (const orderId of toDelete) {
      try {
        // Delete messages and meta
        await Promise.all([
          this.getMessagesRef(orderId).remove(),
          this.getMetaRef(orderId).remove(),
        ]);
        deleted++;
      } catch (error) {
        this.logger.error(`Failed to delete chat for order ${orderId}`, error);
      }
    }

    this.logger.log(`Chat cleanup complete: checked ${toDelete.length}, deleted ${deleted}`);
    return { checked: toDelete.length, deleted };
  }
}