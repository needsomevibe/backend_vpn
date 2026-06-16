import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { SubscriptionStatus, VpnAccount, VpnAccountStatus } from '@prisma/client';
import { jsonSafe } from '../common/serializers/json-safe';
import { PrismaService } from '../prisma/prisma.service';
import { RemnawaveService } from '../remnawave/remnawave.service';

const BYTES_IN_GB = 1024 ** 3;

@Injectable()
export class VpnService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly remnawave: RemnawaveService,
  ) {}

  async getProfile(userId: string) {
    const { vpn, subscription } = await this.getVpnContext(userId);
    const synced = await this.syncVpnAccountFromRemnawave(vpn);

    return {
      status: synced.vpn.status.toLowerCase(),
      subscriptionUrl: synced.vpn.subscriptionUrl,
      trafficUsedGb: this.bytesToGb(synced.vpn.usedTrafficBytes),
      trafficLimitGb: this.bytesToGb(synced.vpn.trafficLimitBytes),
      expiresAt: subscription?.expiresAt ?? synced.vpn.expiresAt,
      nodeLocation: synced.nodeLocation ?? 'US',
    };
  }

  async getUsage(userId: string) {
    const { vpn } = await this.getVpnContext(userId);
    const synced = await this.syncVpnAccountFromRemnawave(vpn);
    return {
      usedTrafficBytes: synced.vpn.usedTrafficBytes.toString(),
      usedTrafficGb: this.bytesToGb(synced.vpn.usedTrafficBytes),
      trafficLimitBytes: synced.vpn.trafficLimitBytes.toString(),
      trafficLimitGb: this.bytesToGb(synced.vpn.trafficLimitBytes),
      nodeLocation: synced.nodeLocation ?? null,
    };
  }

  async enable(userId: string) {
    const { vpn } = await this.getVpnContext(userId, true);
    await this.ensureSubscriptionAllowsVpn(userId);
    await this.remnawave.enableUser(vpn.remnawaveUuid);
    const updated = await this.prisma.vpnAccount.update({
      where: { id: vpn.id },
      data: { status: VpnAccountStatus.ACTIVE },
    });
    return jsonSafe(updated);
  }

  async disable(userId: string) {
    const { vpn } = await this.getVpnContext(userId, true);
    await this.remnawave.disableUser(vpn.remnawaveUuid);
    const updated = await this.prisma.vpnAccount.update({
      where: { id: vpn.id },
      data: { status: VpnAccountStatus.DISABLED },
    });
    return jsonSafe(updated);
  }

  async resetTraffic(userId: string) {
    const { vpn } = await this.getVpnContext(userId, true);
    await this.remnawave.resetTraffic(vpn.remnawaveUuid);
    await this.prisma.vpnAccount.update({
      where: { id: vpn.id },
      data: { usedTrafficBytes: 0 },
    });
    return { success: true };
  }

  async regenerateSubscription(userId: string) {
    const { vpn } = await this.getVpnContext(userId, true);
    await this.remnawave.revokeSubscription(vpn.remnawaveUuid);
    const remote = await this.remnawave.getUserByUuid(vpn.remnawaveUuid);
    const updated = await this.prisma.vpnAccount.update({
      where: { id: vpn.id },
      data: { subscriptionUrl: remote.subscriptionUrl },
    });
    return { subscriptionUrl: updated.subscriptionUrl };
  }

  private async getVpnContext(userId: string, allowDisabled = false) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      include: {
        vpnAccount: true,
        subscriptions: {
          where: {
            status: { in: [SubscriptionStatus.ACTIVE, SubscriptionStatus.TRIALING] },
          },
          orderBy: { expiresAt: 'desc' },
          take: 1,
          include: { plan: true },
        },
      },
    });
    if (!user?.vpnAccount) {
      throw new NotFoundException('VPN account not found');
    }
    if (!allowDisabled && user.vpnAccount.status !== VpnAccountStatus.ACTIVE) {
      throw new ForbiddenException('VPN account is not active');
    }
    return { vpn: user.vpnAccount, subscription: user.subscriptions[0] ?? null };
  }

  private async syncVpnAccountFromRemnawave(vpn: VpnAccount) {
    const usage = await this.remnawave.getUserUsage(vpn.remnawaveUuid);
    const usedTrafficBytes = BigInt(usage.usedTrafficBytes);
    const trafficLimitBytes =
      usage.trafficLimitBytes !== undefined
        ? BigInt(usage.trafficLimitBytes)
        : vpn.trafficLimitBytes;
    const expiresAt = usage.expiresAt ? new Date(usage.expiresAt) : vpn.expiresAt;
    const subscriptionUrl = usage.subscriptionUrl ?? vpn.subscriptionUrl;

    const updated = await this.prisma.vpnAccount.update({
      where: { id: vpn.id },
      data: {
        usedTrafficBytes,
        trafficLimitBytes,
        expiresAt,
        subscriptionUrl,
      },
    });

    return { vpn: updated, nodeLocation: usage.nodeLocation };
  }

  private async ensureSubscriptionAllowsVpn(userId: string) {
    const subscription = await this.prisma.subscription.findFirst({
      where: {
        userId,
        status: { in: [SubscriptionStatus.ACTIVE, SubscriptionStatus.TRIALING] },
        expiresAt: { gt: new Date() },
      },
    });
    if (!subscription) {
      throw new ForbiddenException('Subscription is not active');
    }
  }

  private bytesToGb(bytes: bigint) {
    return Number((Number(bytes) / BYTES_IN_GB).toFixed(2));
  }
}
