import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { SubscriptionStatus, VpnAccountStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RemnawaveService } from '../remnawave/remnawave.service';

@Injectable()
export class SubscriptionExpiryTask {
  private readonly logger = new Logger(SubscriptionExpiryTask.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly remnawave: RemnawaveService,
  ) {}

  @Cron(CronExpression.EVERY_HOUR)
  async disableExpiredSubscriptions() {
    const now = new Date();
    const expired = await this.prisma.subscription.findMany({
      where: {
        status: { in: [SubscriptionStatus.ACTIVE, SubscriptionStatus.TRIALING] },
        expiresAt: { lte: now },
      },
      include: {
        user: {
          include: { vpnAccount: true },
        },
      },
    });

    for (const subscription of expired) {
      const vpn = subscription.user.vpnAccount;
      await this.prisma.subscription.update({
        where: { id: subscription.id },
        data: { status: SubscriptionStatus.EXPIRED },
      });

      if (!vpn || vpn.status === VpnAccountStatus.EXPIRED) {
        continue;
      }

      try {
        await this.remnawave.disableUser(vpn.remnawaveUuid);
      } catch (error) {
        this.logger.error(`Failed to disable Remnawave user ${vpn.remnawaveUuid}`, error);
      }

      await this.prisma.vpnAccount.update({
        where: { id: vpn.id },
        data: { status: VpnAccountStatus.EXPIRED },
      });
    }

    if (expired.length > 0) {
      this.logger.log(`Processed ${expired.length} expired subscriptions`);
    }
  }
}
