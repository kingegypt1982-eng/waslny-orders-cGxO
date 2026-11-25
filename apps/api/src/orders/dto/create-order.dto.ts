import { IsEnum, IsNumber, IsOptional, IsPhoneNumber, IsString, Max, MaxLength, Min, MinLength } from 'class-validator';
import { ShipmentCategory } from '@prisma/client';

export class CreateOrderDto {
  @IsString() @MinLength(2) pickupLabel: string;
  @IsNumber() @Min(-90) @Max(90) pickupLatitude: number;
  @IsNumber() @Min(-180) @Max(180) pickupLongitude: number;
  @IsString() @MinLength(2) deliveryLabel: string;
  @IsNumber() @Min(-90) @Max(90) deliveryLatitude: number;
  @IsNumber() @Min(-180) @Max(180) deliveryLongitude: number;
  @IsEnum(ShipmentCategory) category: ShipmentCategory;
  @IsOptional() @IsNumber() @Min(0.01) estimatedBudget?: number;
  @IsOptional() @IsString() @MaxLength(500) description?: string;
  @IsString() @MinLength(2) recipientName: string;
  @IsPhoneNumber('EG') recipientPhone: string;
}