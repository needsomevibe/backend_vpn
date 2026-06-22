import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  Environment,
  SignedDataVerifier,
  type JWSTransactionDecodedPayload,
} from '@apple/app-store-server-library';
import { SubscriptionStatus, VpnAccountStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RemnawaveService } from '../remnawave/remnawave.service';
import { CheckoutDto } from './dto/checkout.dto';
import { AppleWebhookBody } from './dto/apple-webhook.dto';

const NOTIFY_SUBSCRIBED = 'SUBSCRIBED';
const NOTIFY_DID_RENEW = 'DID_RENEW';
const NOTIFY_EXPIRED = 'EXPIRED';
const NOTIFY_REFUND = 'REFUND';
const NOTIFY_REVOKE = 'REVOKE';

@Injectable()
export class BillingService {
  private readonly logger = new Logger(BillingService.name);
  private readonly bundleId: string;
  private readonly environment: Environment;
  private readonly appleVerifier: SignedDataVerifier | null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly remnawave: RemnawaveService,
    private readonly config: ConfigService,
  ) {
    this.bundleId = config.getOrThrow<string>('APPLE_BUNDLE_ID');
    const isProd = config.get<string>('NODE_ENV') === 'production';
    this.environment = isProd ? Environment.PRODUCTION : Environment.SANDBOX;
    this.appleVerifier = this.buildVerifier();
  }

  // ─── Checkout ────────────────────────────────────────────────────────────────

  async checkout(userId: string, dto: CheckoutDto) {
    const plan = await this.prisma.plan.findFirst({
      where: { id: dto.planId, isActive: true },
    });
    if (!plan) throw new NotFoundException('Plan not found');

    const payment = await this.prisma.payment.create({
      data: {
        userId,
        provider: dto.provider,
        amountCents: plan.priceCents,
        currency: plan.currency,
        status: 'PENDING',
      },
    });

    return {
      checkoutId: payment.id,
      provider: dto.provider,
      status: 'pending',
      amountCents: plan.priceCents,
      currency: plan.currency,
    };
  }

  // ─── Webhook ─────────────────────────────────────────────────────────────────

  async handleWebhook(provider: 'apple' | 'stripe', body: unknown) {
    if (provider === 'apple') {
      return this.handleAppleWebhook(body as AppleWebhookBody);
    }
    return { received: true, provider };
  }

  private async handleAppleWebhook(body: AppleWebhookBody) {
    const { signedPayload } = body;
    if (!signedPayload) {
      this.logger.warn('Apple webhook: missing signedPayload');
      return { received: true, status: 'ignored', reason: 'no_payload' };
    }

    if (!this.appleVerifier) {
      this.logger.error('Apple verifier not configured');
      return { received: true, status: 'ignored', reason: 'verifier_not_configured' };
    }

    let notification: Awaited<ReturnType<SignedDataVerifier['verifyAndDecodeNotification']>>;
    try {
      notification = await this.appleVerifier.verifyAndDecodeNotification(signedPayload);
    } catch (err) {
      this.logger.warn(`Apple webhook verification failed: ${String(err)}`);
      return { received: true, status: 'rejected', reason: 'invalid_signature' };
    }

    const type = notification.notificationType;

    // signedTransactionInfo is a signed JWT string — decode it explicitly
    const signedTxn = notification.data?.signedTransactionInfo as string | undefined;
    let txnInfo: JWSTransactionDecodedPayload | null = null;
    if (signedTxn && this.appleVerifier) {
      try {
        txnInfo = await this.appleVerifier.verifyAndDecodeTransaction(signedTxn);
      } catch {
        this.logger.warn('Could not decode signedTransactionInfo');
      }
    }

    const productId = txnInfo?.productId;
    const originalTransactionId = txnInfo?.originalTransactionId;
    const expiresDateMs = txnInfo?.expiresDate;

    this.logger.log(
      `Apple webhook: ${type} | product=${productId} | txn=${originalTransactionId}`,
    );

    switch (type) {
      case NOTIFY_SUBSCRIBED:
      case NOTIFY_DID_RENEW:
        if (originalTransactionId && productId && expiresDateMs) {
          await this.activateSubscription(
            originalTransactionId,
            productId,
            new Date(expiresDateMs),
          );
        }
        break;

      case NOTIFY_EXPIRED:
      case NOTIFY_REFUND:
      case NOTIFY_REVOKE:
        if (originalTransactionId) {
          await this.deactivateSubscription(originalTransactionId);
        }
        break;

      default:
        this.logger.log(`Apple webhook: unhandled type ${type}`);
    }

    return { received: true, status: 'processed', type };
  }

  // ─── Subscription lifecycle ───────────────────────────────────────────────────

  private async activateSubscription(
    providerSubscriptionId: string,
    productId: string,
    expiresAt: Date,
  ) {
    const plan = await this.prisma.plan.findFirst({
      where: { isActive: true, name: { contains: productId } },
    });

    // Renew existing subscription
    const existing = await this.prisma.subscription.findFirst({
      where: { providerSubscriptionId },
      include: { user: { include: { vpnAccount: true } } },
    });

    if (existing) {
      await this.prisma.subscription.update({
        where: { id: existing.id },
        data: {
          status: SubscriptionStatus.ACTIVE,
          expiresAt,
          ...(plan ? { planId: plan.id } : {}),
        },
      });
      await this.syncVpnAccount(existing.user.vpnAccount?.id, existing.user.vpnAccount?.remnawaveUuid, expiresAt, true);
      this.logger.log(`Subscription renewed: ${existing.id}`);
      return;
    }

    // New purchase — match by most recent pending Apple payment
    const payment = await this.prisma.payment.findFirst({
      where: { provider: 'apple', status: 'PENDING' },
      orderBy: { createdAt: 'desc' },
      include: { user: { include: { vpnAccount: true } } },
    });

    if (!payment) {
      this.logger.warn(`No pending payment found for txn ${providerSubscriptionId}`);
      return;
    }

    await this.prisma.payment.update({
      where: { id: payment.id },
      data: { status: 'SUCCEEDED', providerPaymentId: providerSubscriptionId },
    });

    // Cancel previous active subscriptions
    await this.prisma.subscription.updateMany({
      where: {
        userId: payment.userId,
        status: { in: [SubscriptionStatus.ACTIVE, SubscriptionStatus.TRIALING] },
      },
      data: { status: SubscriptionStatus.CANCELED },
    });

    await this.prisma.subscription.create({
      data: {
        userId: payment.userId,
        planId: plan?.id ?? (await this.defaultPlanId()),
        status: SubscriptionStatus.ACTIVE,
        expiresAt,
        provider: 'apple',
        providerSubscriptionId,
        startedAt: new Date(),
      },
    });

    const vpn = payment.user.vpnAccount;
    await this.syncVpnAccount(vpn?.id, vpn?.remnawaveUuid, expiresAt, true);
    this.logger.log(`Subscription activated for user ${payment.userId}`);
  }

  private async deactivateSubscription(providerSubscriptionId: string) {
    const subscription = await this.prisma.subscription.findFirst({
      where: { providerSubscriptionId },
      include: { user: { include: { vpnAccount: true } } },
    });

    if (!subscription) {
      this.logger.warn(`Subscription not found for txn ${providerSubscriptionId}`);
      return;
    }

    await this.prisma.subscription.update({
      where: { id: subscription.id },
      data: { status: SubscriptionStatus.EXPIRED },
    });

    const vpn = subscription.user.vpnAccount;
    if (vpn && vpn.status !== VpnAccountStatus.EXPIRED) {
      await this.syncVpnAccount(vpn.id, vpn.remnawaveUuid, undefined, false);
    }

    this.logger.log(`Subscription deactivated: ${subscription.id}`);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────────

  private async syncVpnAccount(
    vpnId: string | undefined,
    remnawaveUuid: string | undefined,
    expiresAt: Date | undefined,
    activate: boolean,
  ) {
    if (!vpnId || !remnawaveUuid) return;

    const status = activate ? VpnAccountStatus.ACTIVE : VpnAccountStatus.DISABLED;
    await this.prisma.vpnAccount.update({
      where: { id: vpnId },
      data: { status, ...(expiresAt ? { expiresAt } : {}) },
    });

    try {
      if (activate) {
        await this.remnawave.updateUser(remnawaveUuid, {
          status: 'ACTIVE',
          ...(expiresAt ? { expiresAt } : {}),
        });
      } else {
        await this.remnawave.disableUser(remnawaveUuid);
      }
    } catch (err) {
      this.logger.error(`Failed to sync Remnawave user ${remnawaveUuid}`, err);
    }
  }

  private async defaultPlanId(): Promise<string> {
    const plan = await this.prisma.plan.findFirst({
      where: { isDefault: true, isActive: true },
    });
    if (!plan) throw new NotFoundException('No default plan configured');
    return plan.id;
  }

  private buildVerifier(): SignedDataVerifier | null {
    try {
      // Pass empty roots array — library uses Apple's built-in root CAs
      return new SignedDataVerifier([], true, this.environment, this.bundleId);
    } catch (err) {
      this.logger.warn(`Could not build Apple verifier: ${String(err)}`);
      return null;
    }
  }
}
