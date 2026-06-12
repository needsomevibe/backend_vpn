import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async getMe(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        status: true,
        createdAt: true,
        updatedAt: true,
        vpnAccount: true,
        subscriptions: {
          orderBy: { createdAt: 'desc' },
          take: 1,
          include: { plan: true },
        },
        devices: {
          select: {
            id: true,
            deviceId: true,
            platform: true,
            name: true,
            lastSeenAt: true,
          },
        },
      },
    });
    if (!user) {
      throw new NotFoundException('User not found');
    }
    return { ...user, subscription: user.subscriptions[0] ?? null, subscriptions: undefined };
  }
}
