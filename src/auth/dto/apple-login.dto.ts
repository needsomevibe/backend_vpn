import { ApiProperty } from '@nestjs/swagger';
import { IsOptional, IsString } from 'class-validator';

export class AppleLoginDto {
  @ApiProperty()
  @IsString()
  identityToken: string;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsString()
  authorizationCode?: string;

  @ApiProperty({ example: 'ios-device-uuid' })
  @IsString()
  deviceId: string;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsString()
  fullName?: string;
}
