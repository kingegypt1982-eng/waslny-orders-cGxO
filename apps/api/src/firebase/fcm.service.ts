import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { FirebaseService } from './firebase.service';
import { CaptainStatus, OrderStatus, ShipmentCategory } from '@prisma/client';

@Injectable()
export class FcmService {
  private readonly logger = new Logger(FcmService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly firebase: FirebaseService,
  ) {}

  /**
   * Sends a trip alert FCM notification to a specific captain.
   * This is called when a new order is created and we want to notify eligible captains.
   */
  async sendTripAlert(captainId: string, orderId: string, orderData: {
    reference: string;
    pickupLabel: string;
    deliveryLabel: string;
    category: ShipmentCategory;
    price: number;
    distanceKm: number;
    pickupLatitude: number;
    pickupLongitude: number;
  }): Promise<boolean> {
    try {
      const captain = await this.prisma.captainProfile.findUnique({
        where: { userId: captainId },
        select: { fcmToken: true, isOnline: true, status: true, serviceRadiusKm: true },
      });

      if (!captain || !captain.fcmToken) {
        this.logger.debug(`Captain ${captainId} has no FCM token or not found`);
        return false;
      }

      if (!captain.isOnline || captain.status !== 'ACTIVE') {
        this.logger.debug(`Captain ${captainId} is not online or not active`);
        return false;
      }

      const title = 'طلب جديد متاح';
      const body = `طلب ${orderData.reference}: ${orderData.pickupLabel} → ${orderData.deliveryLabel} (${orderData.price} ج.م)`;

      const data = {
        type: 'trip_alert',
        orderId,
        reference: orderData.reference,
        pickupLabel: orderData.pickupLabel,
        deliveryLabel: orderData.deliveryLabel,
        category: orderData.category,
        price: orderData.price.toString(),
        distanceKm: orderData.distanceKm.toString(),
        pickupLatitude: orderData.pickupLatitude.toString(),
        pickupLongitude: orderData.pickupLongitude.toString(),
      };

      await this.firebase.sendNotification(captain.fcmToken, title, body, data);
      this.logger.log(`Trip alert sent to captain ${captainId} for order ${orderId}`);
      return true;
    } catch (error) {
      this.logger.error(`Failed to send trip alert to captain ${captainId}:`, error);
      // Check if token is invalid/unregistered
      if (error instanceof Error && (
        error.message.includes('registration-token-not-registered') ||
        error.message.includes('invalid-argument') ||
        error.message.includes('UNREGISTERED')
      )) {
        // Clear the invalid token
        await this.prisma.captainProfile.update({
          where: { userId: captainId },
          data: { fcmToken: null },
        });
        this.logger.warn(`Cleared invalid FCM token for captain ${captainId}`);
      }
      return false;
    }
  }

  /**
   * Registers or updates a captain's FCM token.
   */
  async registerFcmToken(captainId: string, token: string): Promise<void> {
    await this.prisma.captainProfile.update({
      where: { userId: captainId },
      data: { fcmToken: token },
    });
    this.logger.log(`FCM token registered for captain ${captainId}`);
  }

  /**
   * Clears a captain's FCM token (e.g., on logout).
   */
  async clearFcmToken(captainId: string): Promise<void> {
    await this.prisma.captainProfile.update({
      where: { userId: captainId },
      data: { fcmToken: null },
    });
    this.logger.log(`FCM token cleared for captain ${captainId}`);
  }

  /**
   * Finds eligible captains for a new order and sends trip alerts to them.
   * Eligibility: ACTIVE status, isOnline=true, within service radius, sufficient wallet balance.
   */
  async notifyEligibleCaptains(orderId: string): Promise<number> {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: {
        id: true,
        reference: true,
        pickupLabel: true,
        deliveryLabel: true,
        category: true,
        price: true,
        distanceKm: true,
        pickupLatitude: true,
        pickupLongitude: true,
        commission: true,
      },
    });

    if (!order) {
      this.logger.warn(`Order ${orderId} not found for captain notification`);
      return 0;
    }

    const settings = await this.prisma.pricingSettings.findUnique({ where: { id: 'default' } });
    const minWalletBalance = Number(settings?.minimumWalletBalance ?? 0);

    // Find all active, online captains with FCM tokens
    const captains = await this.prisma.captainProfile.findMany({
      where: {
        status: 'ACTIVE',
        isOnline: true,
        fcmToken: { not: null },
      },
      select: {
        userId: true,
        fcmToken: true,
        serviceRadiusKm: true,
        lastLat: true,
        lastLng: true,
        isOnline: true,
      },
    });

    let notified = 0;
    for (const captain of captains) {
      // Double-check online status (may have changed)
      if (!captain.isOnline) continue;

      // Check wallet balance
      const wallet = await this.prisma.wallet.findUnique({
        where: { userId: captain.userId },
        select: { balance: true },
      });
      if (!wallet || Number(wallet.balance) < minWalletBalance) continue;

      // Check distance if captain has location
      if (captain.lastLat !== null && captain.lastLng !== null) {
        const distance = this.distanceKm(
          captain.lastLat,
          captain.lastLng,
          order.pickupLatitude,
          order.pickupLongitude,
        );
        const maxRadius = Number(captain.serviceRadiusKm) || 10;
        if (distance > maxRadius) continue;
      }

      const sent = await this.sendTripAlert(captain.userId, orderId, {
        reference: order.reference,
        pickupLabel: order.pickupLabel,
        deliveryLabel: order.deliveryLabel,
        category: order.category,
        price: Number(order.price),
        distanceKm: Number(order.distanceKm),
        pickupLatitude: order.pickupLatitude,
        pickupLongitude: order.pickupLongitude,
      });
      if (sent) notified++;
    }

    this.logger.log(`Notified ${notified} captains for order ${orderId}`);
    return notified;
  }

  /**
   * Cancels trip alerts for an order by sending cancel notifications to all assigned captains.
   * Called when order is cancelled, accepted by another captain, or expires.
   */
  async cancelTripAlert(orderId: string): Promise<void> {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: { captainId: true, reference: true },
    });

    if (!order?.captainId) {
      this.logger.debug(`No captain assigned to order ${orderId} for cancel alert`);
      return;
    }

    try {
      await this.sendCancelAlert(order.captainId, orderId, order.reference ?? 'This order');
      this.logger.log(`Cancelled trip alert sent to captain for order ${orderId}`);
    } catch (error) {
      this.logger.error(`Failed to send cancel alert for order ${orderId}:`, error);
    }
  }

  /**
   * Sends a cancel alert to a specific captain for an order.
   * The mobile app should handle this by stopping any ongoing trip alerts.
   */
  private async sendCancelAlert(captainId: string, orderId: string, reference: string): Promise<void> {
    try {
      const captain = await this.prisma.captainProfile.findUnique({
        where: { userId: captainId },
        select: { fcmToken: true },
      });

      if (!captain?.fcmToken) {
        this.logger.debug(`Captain ${captainId} has no FCM token for cancel`);
        return;
      }

      const data = {
        type: 'trip_cancel',
        orderId,
        reference,
      };

      await this.firebase.sendNotification(captain.fcmToken, 'طلب أُلغي', 'الطلب $reference تم إلغاؤه أو حلل من قبل مندوب آخر', data);
    } catch (error) {
      throw error;
    }
  }

  private distanceKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const radians = (degrees: number) => degrees * Math.PI / 180;
    const deltaLat = radians(lat2 - lat1);
    const deltaLon = radians(lon2 - lon1);
    const arc = Math.sin(deltaLat / 2) ** 2 + Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(deltaLon / 2) ** 2;
    return 6371 * 2 * Math.atan2(Math.sqrt(arc), Math.sqrt(1 - arc));
  }
}