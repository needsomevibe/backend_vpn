import { ApiProperty } from '@nestjs/swagger';
import { IsIn, IsString } from 'class-validator';

export class CheckoutDto {
  @ApiProperty()
  @IsString()
  planId: string;

  @ApiProperty({ enum: ['apple', 'stripe'] })
  @IsIn(['apple', 'stripe'])
  provider: 'apple' | 'stripe';
}
