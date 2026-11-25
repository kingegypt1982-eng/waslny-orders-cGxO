import { Type } from 'class-transformer';
import { PolicyAcknowledgementType } from '@prisma/client';
import { IsDateString, IsEnum, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';

export class AdminAcknowledgementsQueryDto {
  @IsOptional() @IsString() userId?: string;
  @IsOptional() @IsString() orderId?: string;
  @IsOptional() @IsEnum(PolicyAcknowledgementType) type?: PolicyAcknowledgementType;
  @IsOptional() @IsDateString() from?: string;
  @IsOptional() @IsDateString() to?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) skip?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) take?: number;
}