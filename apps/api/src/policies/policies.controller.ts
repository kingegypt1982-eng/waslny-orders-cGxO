import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/auth.decorators';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AcknowledgePolicyDto } from './acknowledge-policy.dto';
import { PoliciesService, PolicyActor } from './policies.service';

@ApiTags('Policies')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('policies')
export class PoliciesController {
  constructor(private readonly policies: PoliciesService) {}

  @Get(':type') get(@Param('type') type: string) { return this.policies.getPolicy(type); }
}

@ApiTags('Policies')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('acknowledgements')
export class AcknowledgementsController {
  constructor(private readonly policies: PoliciesService) {}

  @Post() acknowledge(@CurrentUser() user: PolicyActor, @Body() body: AcknowledgePolicyDto) {
    return this.policies.acknowledge(user, body);
  }
}