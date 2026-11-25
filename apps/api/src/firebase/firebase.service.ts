import { Injectable, OnModuleInit, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { initializeApp, cert, getApp, App } from 'firebase-admin/app';
import { getAuth, Auth } from 'firebase-admin/auth';
import { getDatabase, Database } from 'firebase-admin/database';
import { getMessaging, Messaging } from 'firebase-admin/messaging';

@Injectable()
export class FirebaseService implements OnModuleInit {
  private readonly logger = new Logger(FirebaseService.name);
  private app: App | null = null;

  constructor(private readonly config: ConfigService) {}

  onModuleInit() {
    this.initialize();
  }

  private initialize() {
    if (!this.config.get<boolean>('CHAT_ENABLED')) return;
    const serviceAccountPath = this.config.get<string>('FIREBASE_SERVICE_ACCOUNT_PATH');

    if (!serviceAccountPath) {
      this.logger.warn('FIREBASE_SERVICE_ACCOUNT_PATH not set. Firebase Admin SDK not initialized.');
      return;
    }

    try {
      const serviceAccount = require(serviceAccountPath);
      this.app = initializeApp({
        credential: cert(serviceAccount),
        databaseURL: this.config.get<string>('FIREBASE_DATABASE_URL'),
      });
      this.logger.log('Firebase Admin SDK initialized successfully');
    } catch (error) {
      this.logger.error('Failed to initialize Firebase Admin SDK', error);
      throw error;
    }
  }

  getApp(): App | null {
    return this.app;
  }

  getDatabase(): Database | null {
    if (!this.app) return null;
    return getDatabase(this.app);
  }

  getMessaging(): Messaging | null {
    if (!this.app) return null;
    return getMessaging(this.app);
  }

  async createCustomToken(uid: string, claims?: Record<string, unknown>): Promise<string> {
    if (!this.app) {
      throw new Error('Firebase Admin SDK not initialized');
    }
    return getAuth(this.app).createCustomToken(uid, claims);
  }

  async verifyIdToken(idToken: string) {
    if (!this.app) {
      throw new Error('Firebase Admin SDK not initialized');
    }
    return getAuth(this.app).verifyIdToken(idToken);
  }

  isInitialized(): boolean {
    return this.app !== null;
  }

  async sendNotification(
    token: string,
    title: string,
    body: string,
    data?: Record<string, string>,
  ): Promise<void> {
    if (!this.app) {
      throw new Error('Firebase Admin SDK not initialized');
    }
    const messaging = getMessaging(this.app);
    await messaging.send({
      token,
      notification: { title, body },
      data,
      android: {
        priority: 'high',
        notification: {
          channelId: 'trip_alerts',
          priority: 'max',
          defaultSound: false,
          sound: 'trip_alert_sound',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'trip_alert_sound.wav',
            'content-available': 1,
          },
        },
      },
    });
  }
}