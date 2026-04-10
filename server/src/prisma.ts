import { PrismaClient } from '@prisma/client';

// Singleton Prisma client to reuse connections across handlers.
export const prisma = new PrismaClient();

export const disconnectPrisma = async () => prisma.$disconnect();
