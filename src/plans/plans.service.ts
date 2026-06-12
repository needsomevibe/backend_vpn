import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class PlansService {
  constructor(private readonly prisma: PrismaService) {}

  findAll() {
    return this.prisma.plan.findMany({
      where: { isActive: true },
      orderBy: [{ priceCents: 'asc' }, { trafficLimitGb: 'asc' }],
      select: {
        id: true,
        name: true,
        trafficLimitGb: true,
        deviceLimit: true,
        durationDays: true,
        priceCents: true,
        currency: true,
        isDefault: true,
      },
    });
  }
}
