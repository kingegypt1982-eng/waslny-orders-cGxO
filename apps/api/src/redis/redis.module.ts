import { Global, Injectable, Module, OnModuleDestroy } from '@nestjs/common';
import Redis from 'ioredis';

@Injectable()
export class RedisService implements OnModuleDestroy {
  readonly client: Redis | null;

  constructor() {
    const url = process.env.REDIS_URL;
    this.client = url ? new Redis(url, { lazyConnect: true, maxRetriesPerRequest: 1 }) : null;
    this.client?.connect().catch(() => undefined);
  }

  async updateCaptainLocation(userId: string, latitude: number, longitude: number) {
    if (!this.client) return false;
    await this.client.geoadd('active-captains', longitude, latitude, userId);
    return true;
  }

  async nearbyCaptains(latitude: number, longitude: number, radiusKm = 10) {
    if (!this.client) return [];
    try {
      return await this.client.call(
        'GEOSEARCH', 'active-captains', 'FROMLONLAT', longitude, latitude,
        'BYRADIUS', radiusKm, 'km', 'WITHDIST', 'ASC',
      ) as string[];
    } catch {
      return [];
    }
  }

  async onModuleDestroy() {
    await this.client?.quit().catch(() => undefined);
  }
}

@Global()
@Module({ providers: [RedisService], exports: [RedisService] })
export class RedisModule {}