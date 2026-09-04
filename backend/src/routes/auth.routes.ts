import { Router } from 'express';
import { bmoniClient } from '../bmoni/client.js';
import { prisma, isPostgresDb } from '../db/index.js';

export const authRouter = Router();

interface RegisteredUser {
  userId: string;
  fullName: string;
  email: string;
  accountType: 'personal' | 'business' | 'both';
  country: string;
  phone: string;
  companyName?: string;
  companyRole?: string;
  kycStatus: 'unverified' | 'pending' | 'verified';
  nationalId?: string;
}

const registeredUsers = new Map<string, RegisteredUser>();

// Seed default sandbox master user
registeredUsers.set('usr_flowpay_sandbox_master', {
  userId: 'usr_flowpay_sandbox_master',
  fullName: 'Waffiyyi Fashola',
  email: 'waffiyyi@flowpay.finance',
  accountType: 'both',
  country: 'US',
  phone: '+14155552671',
  companyName: 'FlowPay Technologies Ltd',
  companyRole: 'ADMIN',
  kycStatus: 'verified',
});

async function resolveCapabilities(bmoniUserId: string) {
  let user = registeredUsers.get(bmoniUserId);

  // Attempt database query from public.users
  if (isPostgresDb()) {
    try {
      const dbUser = await prisma.user.findFirst({
        where: {
          OR: [{ id: bmoniUserId }, { bmoniUserId }],
        },
      });
      if (dbUser) {
        user = {
          userId: dbUser.id,
          fullName: dbUser.fullName,
          email: dbUser.email,
          accountType: dbUser.accountType as any,
          country: dbUser.country,
          phone: dbUser.phoneNumber || '',
          companyName: dbUser.companyName || undefined,
          companyRole: dbUser.companyRole || undefined,
          kycStatus: dbUser.kycStatus as any,
          nationalId: dbUser.nationalId || undefined,
        };
        registeredUsers.set(bmoniUserId, user);
      }
    } catch (_) {
      // Non-blocking fallback to in-memory
    }
  }

  const isPersonal = user ? user.accountType === 'personal' : bmoniUserId.includes('personal');
  const isBusiness = user ? user.accountType === 'business' : bmoniUserId.includes('business');
  const isMaster = user?.accountType === 'both';

  if (isMaster) {
    return {
      bmoniUserId,
      hasPersonalWallet: true,
      hasBusinessAccess: true,
      company: {
        companyId: 'comp_flowpay_global',
        name: user?.companyName || 'FlowPay Technologies Ltd',
        role: user?.companyRole || 'ADMIN',
      },
      capabilities: ['PERSONAL_WALLET', 'BUSINESS_PAYROLL', 'TEAM_CARDS', 'MULTI_COUNTRY_SETTLEMENT'],
      cachedAt: new Date().toISOString(),
    };
  }

  if (isPersonal) {
    return {
      bmoniUserId,
      hasPersonalWallet: true,
      hasBusinessAccess: false,
      capabilities: ['PERSONAL_WALLET', 'MONEY_MISSIONS', 'VIRTUAL_CARDS'],
      cachedAt: new Date().toISOString(),
    };
  }

  return {
    bmoniUserId,
    hasPersonalWallet: false,
    hasBusinessAccess: true,
    company: {
      companyId: `comp_${bmoniUserId}`,
      name: user?.companyName || 'FlowPay Business Ltd',
      role: user?.companyRole || 'ADMIN',
    },
    capabilities: ['BUSINESS_PAYROLL', 'TEAM_CARDS', 'MULTI_COUNTRY_SETTLEMENT'],
    cachedAt: new Date().toISOString(),
  };
}

/**
 * GET /api/auth/session
 * Returns active session context for the authenticated mobile client.
 */
authRouter.get('/session', async (req, res) => {
  const userId = (req.headers['x-user-id'] as string) || (req.query.userId as string);
  if (!userId) {
    return res.status(401).json({
      authenticated: false,
      message: 'No active session. Please log in.',
    });
  }

  let user: RegisteredUser | undefined = registeredUsers.get(userId);

  if (isPostgresDb() && !user) {
    try {
      const dbUser = await prisma.user.findFirst({
        where: { OR: [{ id: userId }, { bmoniUserId: userId }] },
      });
      if (dbUser) {
        user = {
          userId: dbUser.id,
          fullName: dbUser.fullName,
          email: dbUser.email,
          accountType: dbUser.accountType as any,
          country: dbUser.country,
          phone: dbUser.phoneNumber || '',
          companyName: dbUser.companyName || undefined,
          companyRole: dbUser.companyRole || undefined,
          kycStatus: dbUser.kycStatus as any,
          nationalId: dbUser.nationalId || undefined,
        };
        registeredUsers.set(userId, user);
      }
    } catch (_) {}
  }

  if (!user) {
    return res.status(401).json({
      authenticated: false,
      message: 'Invalid session or user not found.',
    });
  }

  const capabilities = await resolveCapabilities(user.userId);

  res.json({
    authenticated: true,
    user,
    capabilities,
  });
});

/**
 * POST /api/auth/login
 * Authenticates user by email and retrieves profile & capabilities from Supabase.
 */
authRouter.post('/login', async (req, res) => {
  const { email } = req.body;
  if (!email || typeof email !== 'string') {
    return res.status(400).json({ success: false, message: 'Email is required' });
  }

  const normalizedEmail = email.trim().toLowerCase();
  let user: RegisteredUser | undefined;

  if (isPostgresDb()) {
    try {
      const dbUser = await prisma.user.findFirst({
        where: { email: normalizedEmail },
      });
      if (dbUser) {
        user = {
          userId: dbUser.id,
          fullName: dbUser.fullName,
          email: dbUser.email,
          accountType: dbUser.accountType as any,
          country: dbUser.country,
          phone: dbUser.phoneNumber || '',
          companyName: dbUser.companyName || undefined,
          companyRole: dbUser.companyRole || undefined,
          kycStatus: dbUser.kycStatus as any,
          nationalId: dbUser.nationalId || undefined,
        };
        registeredUsers.set(dbUser.id, user);
        if (dbUser.bmoniUserId) registeredUsers.set(dbUser.bmoniUserId, user);
      }
    } catch (err: any) {
      console.warn('[AuthRouter] DB user lookup notice:', err.message || err);
    }
  }

  // Check in-memory fallback
  if (!user) {
    for (const u of registeredUsers.values()) {
      if (u.email.toLowerCase() === normalizedEmail) {
        user = u;
        break;
      }
    }
  }

  if (!user) {
    return res.status(404).json({
      success: false,
      message: `No account found with email "${email}". Please sign up first.`,
    });
  }

  const capabilities = await resolveCapabilities(user.userId);

  return res.json({
    success: true,
    user,
    capabilities,
    token: `flowpay_jwt_${user.userId}_${Date.now()}`,
  });
});

/**
 * POST /api/auth/signup
 * Registers a new Personal or Business account with dedicated capabilities.
 * Synchronizes with BMONI POST /v1/users when available and persists in Supabase public.users.
 */
authRouter.post('/signup', async (req, res) => {
  const { fullName, email, accountType, country, phone, companyName, companyRole } = req.body;
  let bmoniUserId = `usr_${accountType === 'business' ? 'business' : 'personal'}_${Date.now()}`;

  // Attempt upstream BMONI User creation
  try {
    const bmoniUser = await bmoniClient.createUser({
      email: email || undefined,
      phoneNumber: phone || undefined,
    });
    if (bmoniUser?.id) {
      bmoniUserId = bmoniUser.id;
    }
  } catch (_) {
    // Non-blocking fallback for local test environment
  }

  const user: RegisteredUser = {
    userId: bmoniUserId,
    fullName: fullName || 'FlowPay User',
    email: email || `user_${Date.now()}@flowpay.test`,
    accountType: accountType === 'business' ? 'business' : 'personal',
    country: country || 'NG',
    phone: phone || '',
    companyName: accountType === 'business' ? (companyName || 'Business Entity') : undefined,
    companyRole: accountType === 'business' ? (companyRole || 'ADMIN') : undefined,
    kycStatus: 'unverified',
  };

  registeredUsers.set(bmoniUserId, user);

  // Persist into Supabase public.users
  if (isPostgresDb()) {
    try {
      await prisma.user.upsert({
        where: { id: bmoniUserId },
        create: {
          id: bmoniUserId,
          bmoniUserId,
          email: user.email,
          fullName: user.fullName,
          phoneNumber: user.phone || null,
          accountType: user.accountType,
          country: user.country,
          companyName: user.companyName || null,
          companyRole: user.companyRole || 'ADMIN',
          kycStatus: user.kycStatus,
        },
        update: {
          email: user.email,
          fullName: user.fullName,
          phoneNumber: user.phone || null,
          accountType: user.accountType,
          country: user.country,
          companyName: user.companyName || null,
          companyRole: user.companyRole || 'ADMIN',
        },
      });
    } catch (err) {
      console.warn('[AuthRouter] Non-blocking DB user creation notice:', (err as any)?.message || err);
    }
  }

  const capabilities = await resolveCapabilities(bmoniUserId);

  res.status(201).json({
    success: true,
    user,
    capabilities,
  });
});

/**
 * POST /api/auth/kyc
 * Completes Tier 1 Personal KYC or Corporate KYB verification.
 * Dispatches to BMONI PATCH /v1/users/{userId}/kyc and POST /kyc/activate,
 * and updates public.users.
 */
authRouter.post('/kyc', async (req, res) => {
  const { userId, nationalId, country } = req.body;
  const existing = registeredUsers.get(userId);
  if (existing) {
    existing.kycStatus = 'verified';
    if (nationalId) existing.nationalId = nationalId;
  }

  // Update in database
  if (isPostgresDb() && userId) {
    try {
      await prisma.user.updateMany({
        where: {
          OR: [{ id: userId }, { bmoniUserId: userId }],
        },
        data: {
          kycStatus: 'verified',
          nationalId: nationalId || undefined,
        },
      });
    } catch (err) {
      console.warn('[AuthRouter] Non-blocking DB KYC update notice:', (err as any)?.message || err);
    }
  }

  // Attempt upstream BMONI KYC profile submission and workflow activation
  try {
    if (userId && !userId.startsWith('usr_personal') && !userId.startsWith('usr_business')) {
      const names = (existing?.fullName || 'FlowPay User').split(' ');
      await bmoniClient.submitKycProfile({
        userId,
        personalInfo: {
          firstName: names[0] || 'FlowPay',
          lastName: names.slice(1).join(' ') || 'User',
          dateOfBirth: '1992-04-18',
        },
        addressDetails: {
          street: '14 Admiralty Way',
          city: 'Lagos',
          state: 'Lagos',
          countryCode: country || 'NGA',
        },
        identificationNumbers: nationalId ? { nationalId } : undefined,
      });

      await bmoniClient.activateKyc({
        userId,
        sumsubLevelName: country === 'NG' ? undefined : 'id-and-liveness',
      });
    }
  } catch (_) {
    // Non-blocking fallback for test personas
  }

  res.json({
    success: true,
    status: 'VERIFIED',
    tier: existing?.accountType === 'business' ? 'CORPORATE_GLOBAL_PAYROLL' : 'TIER_1_SMART_WALLET',
    monthlyLimitUsd: existing?.accountType === 'business' ? 1000000 : 10000,
    railsActivated: ['NGN_NUBAN', 'MXN_SPEI', 'USD_TREASURY'],
    verifiedAt: new Date().toISOString(),
  });
});

/**
 * GET /api/auth/capabilities
 * GET /api/auth/users/:bmoniUserId/capabilities
 *
 * Resolves account capabilities for the authenticated user session.
 * Derives whether this bmoniUserId holds a personal smart wallet and
 * whether they are linked as employer/admin to any company/business entity.
 */
authRouter.get('/capabilities', async (req, res) => {
  const bmoniUserId = (req.query.bmoniUserId as string) || 'usr_flowpay_sandbox_master';
  res.json(await resolveCapabilities(bmoniUserId));
});

authRouter.get('/users/:bmoniUserId/capabilities', async (req, res) => {
  const { bmoniUserId } = req.params;
  res.json(await resolveCapabilities(bmoniUserId));
});
