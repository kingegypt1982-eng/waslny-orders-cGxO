import { PolicyAcknowledgementType, ShipmentCategory } from '@prisma/client';
import { IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';

export class AcknowledgePolicyDto {
  @IsEnum(PolicyAcknowledgementType) type: PolicyAcknowledgementType;
  @IsString() @MaxLength(30) policyVersion: string;
  @IsOptional() @IsString() @MaxLength(64) orderId?: string;
  @IsOptional() @IsEnum(ShipmentCategory) category?: ShipmentCategory;
}