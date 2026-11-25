import { Module } from '@nestjs/common';
import { CaptainsController } from './captains.controller';
import { NationalIdCryptoModule } from './national-id-crypto.module';

@Module({
  imports: [NationalIdCryptoModule],
  controllers: [CaptainsController],
  exports: [NationalIdCryptoModule],
})
export class CaptainsModule {}