import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { Test } from '@nestjs/testing';
import * as bcrypt from 'bcrypt';
import { AppleTokenService } from '../src/auth/apple-token.service';
import { AuthService } from '../src/auth/auth.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { RemnawaveService } from '../src/remnawave/remnawave.service';

describe('AuthService', () => {
  const prisma = {
    user: {
      findUnique: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
      findUniqueOrThrow: jest.fn(),
    },
    plan: {
      findFirst: jest.fn(),
    },
    vpnAccount: {
      create: jest.fn(),
    },
    subscription: {
      create: jest.fn(),
    },
    device: {
      upsert: jest.fn(),
    },
    refreshToken: {
      create: jest.fn(),
    },
    $transaction: jest.fn(),
  };

  const remnawave = {
    createUser: jest.fn(),
  };
  const appleTokenService = {
    verifyIdentityToken: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.user.findUnique.mockResolvedValue(null);
    prisma.plan.findFirst.mockResolvedValue({
      id: 'plan-1',
      trafficLimitGb: 100,
      durationDays: 30,
    });
    prisma.user.create.mockResolvedValue({
      id: 'user-12345678',
      email: 'user@example.com',
    });
    remnawave.createUser.mockResolvedValue({
      uuid: 'remote-uuid',
      shortUuid: 'short',
      subscriptionUrl: 'https://sub.yeats.uz/short',
    });
    prisma.$transaction.mockResolvedValue([]);
    prisma.device.upsert.mockResolvedValue({});
    prisma.refreshToken.create.mockResolvedValue({});
    prisma.user.findUniqueOrThrow.mockResolvedValue({
      id: 'user-12345678',
      email: 'user@example.com',
      status: 'ACTIVE',
      createdAt: new Date('2026-06-01T00:00:00.000Z'),
      vpnAccount: null,
      subscriptions: [],
    });
  });

  it('registers a user, provisions Remnawave, and stores a hashed refresh token', async () => {
    const moduleRef = await Test.createTestingModule({
      providers: [
        AuthService,
        JwtService,
        { provide: PrismaService, useValue: prisma },
        { provide: RemnawaveService, useValue: remnawave },
        { provide: AppleTokenService, useValue: appleTokenService },
        { provide: ConfigService, useValue: { getOrThrow: jest.fn() } },
      ],
    })
      .overrideProvider(ConfigService)
      .useValue({
        getOrThrow: (key: string) =>
          key === 'JWT_ACCESS_SECRET' ? 'access-secret' : 'refresh-secret',
      })
      .compile();

    const service = moduleRef.get(AuthService);
    const result = await service.register({
      email: 'User@Example.com',
      password: 'password123',
      deviceId: 'device-1',
    });

    expect(remnawave.createUser).toHaveBeenCalledWith(
      expect.objectContaining({
        username: 'user_user-123',
        trafficLimitBytes: String(100 * 1024 ** 3),
      }),
    );
    expect(result.accessToken).toEqual(expect.any(String));
    expect(result.refreshToken).toEqual(expect.any(String));
    expect(prisma.refreshToken.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        tokenHash: expect.not.stringContaining(result.refreshToken),
      }),
    });
    const tokenHash = prisma.refreshToken.create.mock.calls[0][0].data.tokenHash;
    await expect(bcrypt.compare(result.refreshToken, tokenHash)).resolves.toBe(true);
  });

  it('signs in with Apple and provisions a VPN account for a new user', async () => {
    appleTokenService.verifyIdentityToken.mockResolvedValue({
      subject: 'apple-subject',
      email: 'apple@example.com',
      emailVerified: true,
    });
    prisma.user.findUnique.mockResolvedValue(null);
    prisma.user.create.mockResolvedValue({
      id: 'apple-user-12345678',
      email: 'apple@example.com',
      status: 'ACTIVE',
      passwordHash: null,
    });
    prisma.user.findUniqueOrThrow.mockResolvedValue({
      id: 'apple-user-12345678',
      email: 'apple@example.com',
      status: 'ACTIVE',
      createdAt: new Date('2026-06-01T00:00:00.000Z'),
      vpnAccount: null,
      subscriptions: [],
    });

    const moduleRef = await Test.createTestingModule({
      providers: [
        AuthService,
        JwtService,
        { provide: PrismaService, useValue: prisma },
        { provide: RemnawaveService, useValue: remnawave },
        { provide: AppleTokenService, useValue: appleTokenService },
        { provide: ConfigService, useValue: { getOrThrow: jest.fn() } },
      ],
    })
      .overrideProvider(ConfigService)
      .useValue({
        getOrThrow: (key: string) =>
          key === 'JWT_ACCESS_SECRET' ? 'access-secret' : 'refresh-secret',
      })
      .compile();

    const service = moduleRef.get(AuthService);
    const result = await service.loginWithApple({
      identityToken: 'identity-token',
      deviceId: 'device-apple',
      fullName: 'Apple User',
    });

    expect(prisma.user.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        email: 'apple@example.com',
        passwordHash: null,
        appleSubject: 'apple-subject',
        authProvider: 'apple',
      }),
    });
    expect(remnawave.createUser).toHaveBeenCalledWith(
      expect.objectContaining({ username: 'apple_apple-us' }),
    );
    expect(result.accessToken).toEqual(expect.any(String));
  });
});
