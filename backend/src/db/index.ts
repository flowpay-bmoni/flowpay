import { PrismaClient } from '@prisma/client';
import { env } from '../config/env.js';

// ---------------------------------------------------------------------------
// Prisma Client — singleton pattern (safe for dev hot-reload via tsx)
// ---------------------------------------------------------------------------

const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export const prisma: PrismaClient =
  globalForPrisma.prisma ??
  new PrismaClient({
    log:
      env.NODE_ENV === 'development'
        ? ['query', 'warn', 'error']
        : ['warn', 'error'],
  });

if (env.NODE_ENV !== 'production') {
  globalForPrisma.prisma = prisma;
}

// ---------------------------------------------------------------------------
// Database initialisation — run seed if tables are empty
// ---------------------------------------------------------------------------

export function isPostgresDb(): boolean {
  return (
    env.DATABASE_URL?.startsWith('postgres://') ||
    env.DATABASE_URL?.startsWith('postgresql://') ||
    false
  );
}

export async function initDatabase(): Promise<void> {
  const isPostgres = isPostgresDb();

  if (!isPostgres) {
    console.warn(
      `[DB] Notice: DATABASE_URL is not set to a PostgreSQL URI (${env.DATABASE_URL || 'empty'}).\n` +
        `     Set DATABASE_URL=postgresql://user:pass@host:port/dbname in backend/.env.`
    );
    return;
  }

  try {
    // Prisma handles DDL via migrations; here we only seed demo data
    await seedDemoDataIfNeeded();
    console.log('[DB] PostgreSQL demo records verified.');
  } catch (err: any) {
    console.error('[DB] PostgreSQL initialization note:', err.message || err);
  }
}

async function seedDemoDataIfNeeded(): Promise<void> {
  try {
    const employeeCount = await prisma.employee.count();

    if (employeeCount === 0) {
      // Seed pre-verified BMONI sandbox personas per spec:
      // Employee 1: Bunch Dillon (Nigeria, BVN 99999999999)
      // Employee 2: Samson Jabo (Mexico/Nigeria alt, BVN/NIN 22222222222)
      await prisma.employee.createMany({
        data: [
          {
            id: 'emp_bunch_dillon',
            bmoniUserId: 'usr_bmoni_dillon_ngn',
            partnerId: env.BMONI_PARTNER_ID,
            firstName: 'Bunch',
            lastName: 'Dillon',
            email: 'bunch.dillon@example.ng',
            phoneNumber: '+2348011112222',
            country: 'NG',
            targetCurrency: 'NGN',
            status: 'LINKED',
          },
          {
            id: 'emp_samson_jabo',
            bmoniUserId: 'usr_bmoni_samson_mxn',
            partnerId: env.BMONI_PARTNER_ID,
            firstName: 'Samson',
            lastName: 'Jabo',
            email: 'samson.jabo@example.mx',
            phoneNumber: '+525512345678',
            country: 'MX',
            targetCurrency: 'MXN',
            status: 'LINKED',
          },
        ],
        skipDuplicates: true,
      });

      // Seed default Money Missions
      await prisma.moneyMission.createMany({
        data: [
          {
            id: 'mission_emergency_sweep',
            title: '20% Emergency Fund Auto-Sweep',
            description:
              'Automatically route 20% of international USD disbursements into high-yield NGN savings.',
            ruleType: 'AUTO_SWEEP',
            conditionJson: { trigger: 'DEPOSIT_RECEIVED', currency: 'USD' },
            actionJson: { percentage: 20, destinationCurrency: 'NGN' },
            isActive: true,
          },
          {
            id: 'mission_card_cap',
            title: 'Contractor Card Monthly Cap',
            description:
              'Enforce a strict $500/month spending limit on virtual cards for team contractors.',
            ruleType: 'SPEND_CAP',
            conditionJson: { role: 'CONTRACTOR' },
            actionJson: { monthlyLimitUsdMinor: 50000 },
            isActive: true,
          },
        ],
        skipDuplicates: true,
      });
    }
  } catch (err) {
    console.warn('[DB] Seeding note:', err);
  }
}
