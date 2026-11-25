import { IsDateString, IsIn, IsOptional, IsPhoneNumber, IsString, Matches } from 'class-validator';
import { EGYPT_GOVERNORATE_NAMES, type EgyptGovernorateName } from './national-id.util';

export class CaptainProfileUpdateDto {
  @IsOptional()
  @Matches(/^\d{14}$/, { message: 'National ID must be exactly 14 digits' })
  nationalId?: string;

  @IsOptional()
  @IsPhoneNumber('EG')
  phone?: string;

  @IsOptional()
  @IsIn(EGYPT_GOVERNORATE_NAMES as readonly string[])
  governorate?: EgyptGovernorateName;

  @IsOptional()
  @IsString()
  licenseNumber?: string;

  @IsOptional()
  @IsString()
  vehicleRegistrationNumber?: string;

  @IsOptional()
  @IsString()
  vehiclePlate?: string;

  @IsOptional()
  @IsString()
  vehicleMake?: string;

  @IsOptional()
  @IsString()
  vehicleModel?: string;

  @IsOptional()
  @IsString()
  vehicleColor?: string;

  @IsOptional()
  @IsDateString()
  dateOfBirth?: string;
}
