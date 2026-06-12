import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { APP_GUARD } from '@nestjs/core';
import { AuthModule } from './auth/auth.module';
import { BillingModule } from './billing/billing.module';
import { validateEnv } from './common/env.validation';
import { PlansModule } from './plans/plans.module';
import { PrismaModule } from './prisma/prisma.module';
import { RemnawaveModule } from './remnawave/remnawave.module';
import { TasksModule } from './tasks/tasks.module';
import { UsersModule } from './users/users.module';
import { VpnModule } from './vpn/vpn.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validate: validateEnv,
    }),
    ThrottlerModule.forRoot([
      {
        ttl: 60_000,
        limit: 60,
      },
    ]),
    ScheduleModule.forRoot(),
    PrismaModule,
    RemnawaveModule,
    AuthModule,
    UsersModule,
    VpnModule,
    PlansModule,
    BillingModule,
    TasksModule,
  ],
  providers: [
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule {}
