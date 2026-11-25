import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { TopUpStatus } from '@prisma/client';

export class AdminTopUpsQueryDto {
  @IsOptional() @IsIn(Object.values(TopUpStatus) as string[]) status?: string;
  @IsOptional() @IsString() userId?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(200) take?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) skip?: number;
}
