import { Body, Controller, Headers, HttpCode, Post } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { TopUpsService } from './topups.service';

/**
 * Kashier server-to-server events. Deliberately public (no JWT): authenticity
 * comes from the HMAC signature, verified before any processing.
 * Docs: https://developers.kashier.io/docs/webhooks#prerequisites
 */
@ApiTags('Webhooks')
@Controller('webhooks')
export class WebhooksController {
  constructor(private readonly topUps: TopUpsService) {}

  @Post('kashier')
  @HttpCode(200)
  webhook(@Headers('x-kashier-signature') signature: string | undefined, @Body() body: any) {
    return this.topUps.handleWebhook(signature, body);
  }
}
