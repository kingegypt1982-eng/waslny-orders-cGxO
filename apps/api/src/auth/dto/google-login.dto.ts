import { IsBoolean, IsIn, IsOptional, IsString, MinLength } from 'class-validator';

export class GoogleLoginDto {
  @IsString() @MinLength(10) idToken: string;
  @IsIn(['CLIENT', 'CAPTAIN']) role: 'CLIENT' | 'CAPTAIN';
  @IsOptional() @IsBoolean() termsAccepted?: boolean;
  @IsOptional() @IsString() vehicleType?: string;
  @IsOptional() @IsString() vehiclePlate?: string;
}
