import { BadRequestException, ValidationPipe } from '@nestjs/common';
import { CreateOrderDto } from './dto/create-order.dto';

describe('POST /orders payload validation', () => {
  it('accepts the mobile order-review payload with an Egyptian national phone number', async () => {
    const payload = {
      pickupLabel: 'Cairo, Egypt',
      pickupLatitude: 30,
      pickupLongitude: 31,
      deliveryLabel: 'Airport',
      deliveryLatitude: 30.1,
      deliveryLongitude: 31.1,
      category: 'PURCHASES',
      description: 'Purchases',
      recipientName: 'Client',
      recipientPhone: '01000000000',
    };
    const pipe = new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    });

    await expect(
      pipe.transform(payload, {
        type: 'body',
        metatype: CreateOrderDto,
      }),
    ).resolves.toMatchObject({
      recipientPhone: '01000000000',
    });
  });
});