import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CheckoutDto } from './dto/checkout.dto';

@Injectable()
export class BillingService {
  constructor(private readonly prisma: PrismaService) {}

  async checkout(userId: string, dto: CheckoutDto) {
    const plan = await this.prisma.plan.findFirst({
      where: { id: dto.planId, isActive: true },
    });
    if (!plan) {
      throw new NotFoundException('Plan not found');
    }

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
      message: 'Billing provider integration is not enabled yet.',
    };
  }

  async handleWebhook(provider: 'apple' | 'stripe', body: unknown) {
    return {
      received: true,
      provider,
      status: 'accepted',
      message: 'Webhook placeholder received. Signature validation must be added before production billing.',
      bodyType: typeof body,
    };
  }
}
