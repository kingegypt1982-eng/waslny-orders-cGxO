import { IsOptional, IsString } from 'class-validator';

export class AdminOrderDto {
  @IsOptional() @IsString() captainId?: string;
  @IsOptional() @IsString() status?: string;
}