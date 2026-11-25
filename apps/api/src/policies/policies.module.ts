import { Module } from '@nestjs/common';
import { PoliciesController, AcknowledgementsController } from './policies.controller';
import { PoliciesService } from './policies.service';

@Module({ controllers: [PoliciesController, AcknowledgementsController], providers: [PoliciesService], exports: [PoliciesService] })
export class PoliciesModule {}