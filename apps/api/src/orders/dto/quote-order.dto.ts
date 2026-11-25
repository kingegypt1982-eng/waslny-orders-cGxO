import { IsNumber, Max, Min } from 'class-validator';

export class QuoteOrderDto {
  @IsNumber() @Min(-90) @Max(90) pickupLatitude: number;
  @IsNumber() @Min(-180) @Max(180) pickupLongitude: number;
  @IsNumber() @Min(-90) @Max(90) deliveryLatitude: number;
  @IsNumber() @Min(-180) @Max(180) deliveryLongitude: number;
}