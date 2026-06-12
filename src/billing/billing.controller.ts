import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { JwtUser } from '../common/types/jwt-user.type';
import { BillingService } from './billing.service';
import { CheckoutDto } from './dto/checkout.dto';

@ApiTags('Billing')
@Controller('billing')
export class BillingController {
  constructor(private readonly billingService: BillingService) {}

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('checkout')
  checkout(@CurrentUser() user: JwtUser, @Body() dto: CheckoutDto) {
    return this.billingService.checkout(user.sub, dto);
  }

  @Post('webhook/apple')
  appleWebhook(@Body() body: unknown) {
    return this.billingService.handleWebhook('apple', body);
  }

  @Post('webhook/stripe')
  stripeWebhook(@Body() body: unknown) {
    return this.billingService.handleWebhook('stripe', body);
  }
}
