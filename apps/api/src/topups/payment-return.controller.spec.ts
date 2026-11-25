import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as request from 'supertest';
import { PaymentReturnController } from './payment-return.controller';

describe('PaymentReturnController (public page)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      controllers: [PaymentReturnController],
    }).compile();
    app = module.createNestApplication();
    app.setGlobalPrefix('api/v1');
    await app.init();
  });

  afterAll(async () => {
    await app?.close();
  });

  it('serves the bilingual page under the API prefix without any token', async () => {
    const response = await request(app.getHttpServer())
      .get('/api/v1/payment-return')
      .expect(200);

    expect(response.headers['content-type']).toMatch(/text\/html/);
    expect(response.headers['cache-control']).toContain('no-store');
    expect(response.text).toContain('ارجع للتطبيق، تأكيد الدفع بيتم تلقائياً');
    expect(response.text).toContain('Return to the app — payment confirmation is automatic.');
    expect(response.text).not.toMatch(/api[_-]?key|secret|signature/i);
  });

  it('does not answer at the unprefixed root path', async () => {
    await request(app.getHttpServer()).get('/payment-return').expect(404);
  });
});
