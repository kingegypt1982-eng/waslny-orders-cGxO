import { INestApplication, UnauthorizedException } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as request from 'supertest';
import { TopUpsService } from './topups.service';
import { WebhooksController } from './webhooks.controller';

// Nest application bootstrap is slow under the full parallel suite on this
// machine; give this HTTP contract suite enough time instead of disabling it.
jest.setTimeout(30000);

describe('WebhooksController (Kashier HTTP contract)', () => {
  let app: INestApplication;
  const handleWebhook = jest.fn();

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      controllers: [WebhooksController],
      providers: [{ provide: TopUpsService, useValue: { handleWebhook } }],
    }).compile();
    app = module.createNestApplication();
    app.setGlobalPrefix('api/v1');
    await app.init();
  });

  afterAll(async () => {
    await app?.close();
  });

  beforeEach(() => {
    handleWebhook.mockReset();
  });

  const payload = { data: { merchantOrderId: 'topup_ref', amount: 50, currency: 'EGP' } };

  it('answers 200 for an accepted event', async () => {
    handleWebhook.mockResolvedValue({ acknowledged: true });

    const response = await request(app.getHttpServer())
      .post('/api/v1/webhooks/kashier')
      .set('x-kashier-signature', 'placeholder')
      .send(payload)
      .expect(200);

    expect(response.body).toEqual({ acknowledged: true });
    expect(handleWebhook).toHaveBeenCalledWith('placeholder', payload);
  });

  it('answers 401 with no signature detail when verification fails', async () => {
    handleWebhook.mockRejectedValue(new UnauthorizedException());

    const response = await request(app.getHttpServer())
      .post('/api/v1/webhooks/kashier')
      .set('x-kashier-signature', 'bad')
      .send(payload)
      .expect(401);

    expect(response.body).toEqual({ statusCode: 401, message: 'Unauthorized' });
    expect(JSON.stringify(response.body)).not.toMatch(/signature|hmac|key/i);
    expect(handleWebhook).toHaveBeenCalledTimes(1);
  });

  it('answers 200 for unknown references and replays', async () => {
    handleWebhook.mockResolvedValue({ acknowledged: true });

    await request(app.getHttpServer())
      .post('/api/v1/webhooks/kashier')
      .send({ data: { merchantOrderId: 'never-seen' } })
      .expect(200);
    await request(app.getHttpServer())
      .post('/api/v1/webhooks/kashier')
      .send(payload)
      .expect(200);

    expect(handleWebhook).toHaveBeenCalledTimes(2);
  });
});
