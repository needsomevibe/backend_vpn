import { ApiProperty } from '@nestjs/swagger';
import { IsEmail, IsOptional, IsString, MinLength } from 'class-validator';

export class RegisterDto {
  @ApiProperty({ example: 'user@example.com' })
  @IsEmail()
  email: string;

  @ApiProperty({ minLength: 8 })
  @IsString()
  @MinLength(8)
  password: string;

  @ApiProperty({ example: 'ios-device-uuid' })
  @IsString()
  deviceId: string;

  @ApiProperty({ example: 'iPhone 15 Pro', required: false })
  @IsOptional()
  @IsString()
  deviceName?: string;
}
