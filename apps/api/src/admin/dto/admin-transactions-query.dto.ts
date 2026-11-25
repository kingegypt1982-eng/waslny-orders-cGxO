import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { WalletTransactionType } from '@prisma/client';

export class AdminTransactionsQueryDto {
  @IsOptional() @IsIn(Object.values(WalletTransactionType) as string[]) type?: string;
  @IsOptional() @IsString() userId?: string;
  @IsOptional() @IsString() orderId?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(200) take?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) skip?: number;
}
