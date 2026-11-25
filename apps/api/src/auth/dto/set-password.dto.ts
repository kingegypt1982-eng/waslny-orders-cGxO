import { IsOptional, IsString, MinLength } from 'class-validator';

export class SetPasswordDto {
  /** Required only when the account already has a password (change flow). */
  @IsOptional()
  @IsString()
  currentPassword?: string;

  @IsString()
  @MinLength(8)
  newPassword: string;
}
