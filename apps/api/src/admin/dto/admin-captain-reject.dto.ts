import { IsString, MinLength } from 'class-validator';

export class AdminCaptainRejectDto {
  @IsString()
  @MinLength(3)
  reason: string;
}
