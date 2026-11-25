import { IsOptional, IsString, MaxLength } from 'class-validator';

export class ProofNoteDto {
  @IsOptional() @IsString() @MaxLength(500) note?: string;
}
