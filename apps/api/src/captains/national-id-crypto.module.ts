import { Module } from '@nestjs/common';
import { NationalIdCryptoService } from './national-id-crypto.service';

@Module({
  providers: [NationalIdCryptoService],
  exports: [NationalIdCryptoService],
})
export class NationalIdCryptoModule {}
