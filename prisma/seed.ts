import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  await prisma.plan.upsert({
    where: { name: 'Free' },
    create: {
      name: 'Free',
      trafficLimitGb: 100,
      deviceLimit: 1,
      durationDays: 30,
      priceCents: 0,
      currency: 'USD',
      isDefault: true,
      isActive: true,
    },
    update: {
      trafficLimitGb: 100,
      deviceLimit: 1,
      durationDays: 30,
      priceCents: 0,
      currency: 'USD',
      isDefault: true,
      isActive: true,
    },
  });

  await prisma.plan.upsert({
    where: { name: 'Premium Monthly' },
    create: {
      name: 'Premium Monthly',
      trafficLimitGb: 500,
      deviceLimit: 5,
      durationDays: 30,
      priceCents: 999,
      currency: 'USD',
      isActive: true,
    },
    update: {
      trafficLimitGb: 500,
      deviceLimit: 5,
      durationDays: 30,
      priceCents: 999,
      currency: 'USD',
      isActive: true,
    },
  });
}

main()
  .then(async () => {
    await prisma.$disconnect();
  })
  .catch(async (error) => {
    console.error(error);
    await prisma.$disconnect();
    process.exit(1);
  });
