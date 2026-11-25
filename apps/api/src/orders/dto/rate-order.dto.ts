import { Equals, IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

export class RateOrderDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(5)
  stars?: number;

  /** @deprecated Use `stars`. Kept temporarily for older mobile builds. */
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(5)
  score?: number;

  // Always derived from the order by the server; never accepted from the body.
  @Equals(undefined, { message: 'rateeId is derived from the order and cannot be supplied' })
  rateeId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  comment?: string;
}
