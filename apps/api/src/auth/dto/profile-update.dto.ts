import { IsOptional, IsPhoneNumber, IsString, Matches, MaxLength, MinLength } from 'class-validator';

export class ProfileUpdateDto {
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  @Matches(/\S/)
  name: string;

  @IsOptional()
  @IsPhoneNumber('EG')
  phone?: string | null;
}