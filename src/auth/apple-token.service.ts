import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export type AppleIdentity = {
  subject: string;
  email: string;
  emailVerified: boolean;
};

@Injectable()
export class AppleTokenService {
  private readonly bundleId: string;

  constructor(config: ConfigService) {
    this.bundleId = config.getOrThrow<string>('APPLE_BUNDLE_ID');
  }

  async verifyIdentityToken(identityToken: string): Promise<AppleIdentity> {
    try {
      const { createRemoteJWKSet, jwtVerify } = await import('jose');
      const jwks = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
      const { payload } = await jwtVerify(identityToken, jwks, {
        issuer: 'https://appleid.apple.com',
        audience: this.bundleId,
      });
      if (!payload.sub || typeof payload.sub !== 'string') {
        throw new UnauthorizedException('Apple identity token is missing subject');
      }
      if (!payload.email || typeof payload.email !== 'string') {
        throw new UnauthorizedException('Apple identity token is missing email');
      }
      return {
        subject: payload.sub,
        email: payload.email.toLowerCase(),
        emailVerified: payload.email_verified === true || payload.email_verified === 'true',
      };
    } catch (error) {
      if (error instanceof UnauthorizedException) {
        throw error;
      }
      throw new UnauthorizedException('Apple identity token is invalid');
    }
  }
}
