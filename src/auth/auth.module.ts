import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { RemnawaveModule } from '../remnawave/remnawave.module';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { AppleTokenService } from './apple-token.service';
import { JwtStrategy } from './jwt.strategy';

@Module({
  imports: [PassportModule, JwtModule.register({}), RemnawaveModule],
  controllers: [AuthController],
  providers: [AuthService, AppleTokenService, JwtStrategy],
  exports: [AuthService],
})
export class AuthModule {}
