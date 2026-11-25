import { IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class RespondInvoiceDto {
  @IsIn(['CONFIRMED', 'DISPUTED']) action: 'CONFIRMED' | 'DISPUTED';
  @IsOptional() @IsString() @MinLength(2) @MaxLength(500) reason?: string;
}