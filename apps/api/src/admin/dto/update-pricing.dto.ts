import { IsArray, IsEnum, IsNumber, IsOptional, Max, Min } from 'class-validator';
import { ShipmentCategory } from '@prisma/client';

export class UpdatePricingDto {
  @IsNumber() @Min(0) basePrice: number;
  @IsNumber() @Min(0) pricePerKm: number;
  @IsNumber() @Min(0) @Max(100) commissionPercent: number;
  @IsNumber() @Min(0) minimumWalletBalance: number;
  @IsOptional() @IsNumber() @Min(1) minTopUpAmount?: number;
  @IsOptional() @IsNumber() @Min(1) maxTopUpAmount?: number;
  @IsOptional() @IsNumber() @Min(0) @Max(20) paymentFeePercent?: number;
  @IsOptional() @IsNumber() @Min(0) paymentFeeFixed?: number;
  @IsOptional() @IsArray() @IsEnum(ShipmentCategory, { each: true }) disabledCategories?: ShipmentCategory[];
}