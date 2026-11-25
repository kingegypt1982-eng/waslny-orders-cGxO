import { Type } from 'class-transformer';
import { IsDateString, IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { OrderStatus } from '@prisma/client';

const STATUSES = Object.values(OrderStatus) as string[];

export class AdminOrdersQueryDto {
  @IsOptional() @IsIn(STATUSES) status?: string;
  @IsOptional() @IsDateString() from?: string;
  @IsOptional() @IsDateString() to?: string;
  @IsOptional() @IsString() captainId?: string;
  @IsOptional() @IsString() clientId?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(200) take?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) skip?: number;
}
