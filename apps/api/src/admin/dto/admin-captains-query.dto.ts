import { IsIn, IsOptional } from 'class-validator';
import { CaptainStatus } from '@prisma/client';

export class AdminCaptainsQueryDto {
  @IsOptional() @IsIn(Object.values(CaptainStatus) as string[]) status?: string;
}
