import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { BillingController } from './billing.controller';
import { BillingService } from './billing.service';
import { RemnawaveModule } from '../remnawave/remnawave.module';

@Module({
  imports: [ConfigModule, RemnawaveModule],
  controllers: [BillingController],
  providers: [BillingService],
})
export class BillingModule {}
