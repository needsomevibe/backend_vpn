import {
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { SubscriptionStatus } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { randomUUID } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { RemnawaveApiError, RemnawaveService } from '../remnawave/remnawave.service';
import { jsonSafe } from '../common/serializers/json-safe';
import { AppleTokenService } from './apple-token.service';
import { AppleLoginDto } from './dto/apple-login.dto';
import { LoginDto } from './dto/login.dto';
import { RegisterDto } from './dto/register.dto';

const ACCESS_TTL = '15m';
const REFRESH_TTL_DAYS = 30;
const BYTES_IN_GB = 1024 ** 3;

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly remnawave: RemnawaveService,
    private readonly appleTokenService: AppleTokenService,
  ) {}

  async register(dto: RegisterDto) {
    const email = dto.email.toLowerCase();
    const existing = await this.prisma.user.findUnique({ where: { email } });
    if (existing) {
      if (
        existing.status === 'ACTIVE' &&
        existing.passwordHash &&
        (await bcrypt.compare(dto.password, existing.passwordHash))
      ) {
        await this.restoreVpnIfMissing(existing.id);
        if (dto.deviceId) {
          await this.prisma.device.upsert({
            where: { userId_deviceId: { userId: existing.id, deviceId: dto.deviceId } },
            create: {
              userId: existing.id,
              deviceId: dto.deviceId,
              platform: 'ios',
              name: dto.deviceName,
            },
            update: { lastSeenAt: new Date(), name: dto.deviceName },
          });
        }
        return this.buildAuthResponse(existing.id, existing.email, dto.deviceId);
      }
      throw new ConflictException('Email is already registered');
    }

    const plan = await this.prisma.plan.findFirst({
      where: { isDefault: true, isActive: true },
    });
    if (!plan) {
      throw new ConflictException('Default plan is not configured');
    }

    const passwordHash = await bcrypt.hash(dto.password, 12);

    const user = await this.prisma.user.create({
      data: {
        email,
        passwordHash,
        devices: {
          create: {
            deviceId: dto.deviceId,
            platform: 'ios',
            name: dto.deviceName,
          },
        },
      },
    });

    try {
      await this.provisionVpnForUser(user.id, email, plan);
    } catch (error) {
      await this.prisma.user.delete({ where: { id: user.id } }).catch(() => undefined);
      throw error;
    }

    return this.buildAuthResponse(user.id, email, dto.deviceId);
  }

  async login(dto: LoginDto) {
    const email = dto.email.toLowerCase();
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user || user.status !== 'ACTIVE' || !user.passwordHash) {
      throw new UnauthorizedException('Invalid credentials');
    }
    const passwordMatches = await bcrypt.compare(dto.password, user.passwordHash);
    if (!passwordMatches) {
      throw new UnauthorizedException('Invalid credentials');
    }

    if (dto.deviceId) {
      await this.prisma.device.upsert({
        where: { userId_deviceId: { userId: user.id, deviceId: dto.deviceId } },
        create: { userId: user.id, deviceId: dto.deviceId, platform: 'ios' },
        update: { lastSeenAt: new Date() },
      });
    }

    return this.buildAuthResponse(user.id, user.email, dto.deviceId);
  }

  async loginWithApple(dto: AppleLoginDto) {
    const identity = await this.appleTokenService.verifyIdentityToken(dto.identityToken);
    // Apple subject is stable and always present, so it is the primary key for
    // returning sign-ins (where the token no longer carries the email claim).
    let user = await this.prisma.user.findUnique({
      where: { appleSubject: identity.subject },
    });

    if (!user && identity.email) {
      const existingByEmail = await this.prisma.user.findUnique({
        where: { email: identity.email },
      });
      if (existingByEmail) {
        user = await this.prisma.user.update({
          where: { id: existingByEmail.id },
          data: {
            appleSubject: identity.subject,
            authProvider: existingByEmail.passwordHash ? 'email_apple' : 'apple',
          },
        });
      }
    }

    if (!user) {
      const plan = await this.prisma.plan.findFirst({
        where: { isDefault: true, isActive: true },
      });
      if (!plan) {
        throw new ConflictException('Default plan is not configured');
      }
      // New account with a hidden email (e.g. the user already authorized the
      // app before, so Apple withholds it): synthesize a stable unique address
      // from the Apple subject so provisioning still has a username.
      const email = identity.email ?? `${identity.subject}@appleid.local`;
      user = await this.prisma.user.create({
        data: {
          email,
          passwordHash: null,
          appleSubject: identity.subject,
          authProvider: 'apple',
          devices: {
            create: {
              deviceId: dto.deviceId,
              platform: 'ios',
              name: dto.fullName,
            },
          },
        },
      });
      try {
        await this.provisionVpnForUser(user.id, user.email, plan);
      } catch (error) {
        await this.prisma.user.delete({ where: { id: user.id } }).catch(() => undefined);
        throw error;
      }
    } else if (user.status !== 'ACTIVE') {
      throw new UnauthorizedException('User is not active');
    }

    await this.prisma.device.upsert({
      where: { userId_deviceId: { userId: user.id, deviceId: dto.deviceId } },
      create: { userId: user.id, deviceId: dto.deviceId, platform: 'ios', name: dto.fullName },
      update: { lastSeenAt: new Date(), name: dto.fullName },
    });

    return this.buildAuthResponse(user.id, user.email, dto.deviceId);
  }

  async refresh(refreshToken: string) {
    const payload = await this.verifyRefreshToken(refreshToken);
    const stored = await this.prisma.refreshToken.findUnique({
      where: { id: payload.jti },
      include: { user: true },
    });
    if (!stored || stored.revokedAt || stored.expiresAt <= new Date()) {
      throw new UnauthorizedException('Refresh token is invalid');
    }
    const matches = await bcrypt.compare(refreshToken, stored.tokenHash);
    if (!matches || stored.user.status !== 'ACTIVE') {
      throw new UnauthorizedException('Refresh token is invalid');
    }

    await this.prisma.refreshToken.update({
      where: { id: stored.id },
      data: { revokedAt: new Date() },
    });
    return this.buildAuthResponse(stored.user.id, stored.user.email, stored.deviceId ?? undefined);
  }

  async logout(refreshToken: string) {
    try {
      const payload = await this.verifyRefreshToken(refreshToken);
      await this.prisma.refreshToken.updateMany({
        where: { id: payload.jti, revokedAt: null },
        data: { revokedAt: new Date() },
      });
    } catch {
      return { success: true };
    }
    return { success: true };
  }

  private async buildAuthResponse(userId: string, email: string, deviceId?: string) {
    await this.restoreVpnIfMissing(userId);

    const refreshTokenId = randomUUID();
    const refreshExpiresAt = new Date(Date.now() + REFRESH_TTL_DAYS * 86_400_000);
    const [accessToken, refreshToken] = await Promise.all([
      this.jwt.signAsync(
        { sub: userId, email },
        {
          secret: this.config.getOrThrow<string>('JWT_ACCESS_SECRET'),
          expiresIn: ACCESS_TTL,
        },
      ),
      this.jwt.signAsync(
        { sub: userId, email, jti: refreshTokenId },
        {
          secret: this.config.getOrThrow<string>('JWT_REFRESH_SECRET'),
          expiresIn: `${REFRESH_TTL_DAYS}d`,
        },
      ),
    ]);

    await this.prisma.refreshToken.create({
      data: {
        id: refreshTokenId,
        userId,
        tokenHash: await bcrypt.hash(refreshToken, 12),
        deviceId,
        expiresAt: refreshExpiresAt,
      },
    });

    const profile = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        status: true,
        createdAt: true,
        vpnAccount: true,
        subscriptions: {
          orderBy: { createdAt: 'desc' },
          take: 1,
          include: { plan: true },
        },
      },
    });

    return jsonSafe({
      accessToken,
      refreshToken,
      user: {
        id: profile.id,
        email: profile.email,
        status: profile.status,
        createdAt: profile.createdAt,
        vpn: profile.vpnAccount,
        subscription: profile.subscriptions[0] ?? null,
      },
    });
  }

  private async verifyRefreshToken(refreshToken: string) {
    try {
      return await this.jwt.verifyAsync<{ sub: string; email: string; jti: string }>(
        refreshToken,
        { secret: this.config.getOrThrow<string>('JWT_REFRESH_SECRET') },
      );
    } catch {
      throw new UnauthorizedException('Refresh token is invalid');
    }
  }

  private buildVpnUsername(userId: string, email: string) {
    const prefix = email.split('@')[0].replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 20);
    return `${prefix || 'user'}_${userId.slice(0, 8)}`;
  }

  private async provisionVpnForUser(
    userId: string,
    email: string,
    plan: { id: string; trafficLimitGb: number; durationDays: number },
  ) {
    const now = new Date();
    const expiresAt = new Date(now.getTime() + plan.durationDays * 86_400_000);
    const trafficLimitBytes = BigInt(plan.trafficLimitGb) * BigInt(BYTES_IN_GB);
    const username = this.buildVpnUsername(userId, email);
    const remote = await this.remnawave.createUser({
      username,
      trafficLimitBytes: trafficLimitBytes.toString(),
      expiresAt,
    });

    await this.prisma.$transaction([
      this.prisma.vpnAccount.create({
        data: {
          userId,
          remnawaveUuid: remote.uuid,
          remnawaveShortUuid: remote.shortUuid,
          username,
          status: 'ACTIVE',
          trafficLimitBytes,
          expiresAt,
          subscriptionUrl: remote.subscriptionUrl,
        },
      }),
      this.prisma.subscription.create({
        data: {
          userId,
          planId: plan.id,
          status: SubscriptionStatus.TRIALING,
          startedAt: now,
          expiresAt,
          provider: 'internal',
        },
      }),
    ]);
  }

  private async restoreVpnIfMissing(userId: string) {
    const account = await this.prisma.vpnAccount.findUnique({
      where: { userId },
      include: {
        user: {
          select: {
            subscriptions: {
              where: {
                status: { in: [SubscriptionStatus.ACTIVE, SubscriptionStatus.TRIALING] },
              },
              orderBy: { expiresAt: 'desc' },
              take: 1,
            },
          },
        },
      },
    });
    if (!account) {
      return;
    }

    try {
      await this.remnawave.getUserByUuid(account.remnawaveUuid);
      return;
    } catch (error) {
      if (!this.isRemnawaveNotFound(error)) {
        throw error;
      }
    }

    const expiresAt = account.user.subscriptions[0]?.expiresAt ?? account.expiresAt;
    const remote = await this.remnawave.createUser({
      username: account.username,
      trafficLimitBytes: account.trafficLimitBytes.toString(),
      expiresAt,
    });

    await this.prisma.vpnAccount.update({
      where: { id: account.id },
      data: {
        remnawaveUuid: remote.uuid,
        remnawaveShortUuid: remote.shortUuid,
        subscriptionUrl: remote.subscriptionUrl,
        expiresAt,
        status: 'ACTIVE',
      },
    });
  }

  private isRemnawaveNotFound(error: unknown) {
    return error instanceof RemnawaveApiError && error.upstreamStatus === 404;
  }
}
