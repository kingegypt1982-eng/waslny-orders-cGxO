import { IsEmail, IsIn, IsOptional, IsPhoneNumber, IsString, MinLength } from 'class-validator';

export class RegisterDto {
  @IsEmail() email: string;
  @MinLength(8) password: string;
  @IsString() @MinLength(2) name: string;
  @IsPhoneNumber('EG') phone: string;
  @IsIn(['CLIENT', 'CAPTAIN']) role: 'CLIENT' | 'CAPTAIN';
  @IsOptional() @IsString() nationalIdDocument?: string;
  @IsOptional() @IsString() licenseDocument?: string;
  @IsOptional() @IsString() vehicleDocument?: string;
  @IsOptional() @IsString() vehicleType?: string;
  @IsOptional() @IsString() vehiclePlate?: string;
}