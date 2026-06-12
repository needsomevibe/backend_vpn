import { Module } from '@nestjs/common';
import { RemnawaveModule } from '../remnawave/remnawave.module';
import { SubscriptionExpiryTask } from './subscription-expiry.task';

@Module({
  imports: [RemnawaveModule],
  providers: [SubscriptionExpiryTask],
})
export class TasksModule {}
