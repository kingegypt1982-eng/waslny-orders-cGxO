import { Type } from 'class-transformer';
import { IsNumber, Max, Min } from 'class-validator';

/** Coordinates the captain's device reports while polling the orders feed. */
export class AvailableOrdersQueryDto {
  @Type(() => Number) @IsNumber() @Min(-90) @Max(90) latitude: number;
  @Type(() => Number) @IsNumber() @Min(-180) @Max(180) longitude: number;
}
