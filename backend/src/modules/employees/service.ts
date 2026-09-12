import crypto from 'node:crypto';
import { bmoniClient } from '../../bmoni/client.js';
import { prisma, isPostgresDb } from '../../db/index.js';
import { env } from '../../config/env.js';
import { mailService } from '../mail/service.js';
import { findUserByQuery } from '../../routes/auth.routes.js';

export type EmployeeLifecycleStage =
  | 'INVITED'
  | 'CREATED'
  | 'WALLET_PENDING'
  | 'KYC_PENDING'
  | 'ONBOARDING'
  | 'READY'
  | 'FAILED'
  | 'LINKED'
  | 'ACTIVE';

export type EmployeeRecord = NonNullable<Awaited<ReturnType<typeof prisma.employee.findFirst>>>;

export interface CreateEmployeeInput {
  firstName: string;
  lastName: string;
  email: string;
  phoneNumber?: string;
  country: string;
  targetCurrency?: string;
  payrollAmountMinor: number;
  payrollCurrency?: string;
  employerName?: string;
  companyName?: string;
  businessId?: string;
}

export interface EmployeeInviteRecord {
  token: string;
  employeeId: string;
  bmoniUserId?: string;
  email: string;
  firstName: string;
  lastName: string;
  country: string;
  targetCurrency: string;
  payrollAmountMinor: number;
  expiresAt: Date;
  usedAt?: Date;
}

export interface LinkEmployeeWalletInput {
  employeeId?: string;
  inviteToken: string;
  bmoniUserId: string;
  walletAddress: string;
  walletId?: string;
  requestingUserId?: string;
  requestingEmail?: string;
}

// In-memory invite registry (72h TTL) and fallback store
export const employeeInvites = new Map<string, EmployeeInviteRecord>();
export const inMemoryEmployees = new Map<string, any>();

export class EmployeeService {
  static validateCreateInput(data: CreateEmployeeInput): { valid: boolean; errors: string[] } {
    const errors: string[] = [];
    if (!data.firstName || typeof data.firstName !== 'string' || data.firstName.trim().length === 0) errors.push('firstName is required and cannot be empty');
    if (!data.lastName || typeof data.lastName !== 'string' || data.lastName.trim().length === 0) errors.push('lastName is required and cannot be empty');
    if (!data.email || typeof data.email !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(data.email.trim())) errors.push('A valid email address is required');
    const country = (data.country || '').trim().toUpperCase();
    const supportedCountries = ['NG', 'MX', 'CA'];
    if (!supportedCountries.includes(country)) errors.push(`country must be one of: ${supportedCountries.join(', ')} (received: ${data.country})`);
    if (!Number.isInteger(data.payrollAmountMinor) || data.payrollAmountMinor <= 0) errors.push('payrollAmountMinor must be a positive integer in minor currency units (e.g. 100000 = $1,000.00)');
    return { valid: errors.length === 0, errors };
  }

  static resolveCurrency(country: string): string {
    switch (country.toUpperCase()) { case 'NG': return 'NGN'; case 'MX': return 'MXN'; case 'CA': return 'CAD'; default: return 'USD'; }
  }

  // BMONI requires an E.164 phone number for user creation. If none was given
  // or a domestic format was provided, normalize to E.164. Shared by both
  // createEmployee and retryBmoniUserCreation.
  static buildEffectivePhone(phoneNumber: string | undefined | null, country: string): string {
    const trimmed = (phoneNumber || '').trim();
    const c = country.toUpperCase();

    if (trimmed) {
      if (trimmed.startsWith('+')) {
        return trimmed;
      }
      const digits = trimmed.replace(/\D/g, '');
      if (c === 'NG') {
        if (digits.startsWith('234') && digits.length >= 13) return `+${digits}`;
        if (digits.startsWith('0') && digits.length === 11) return `+234${digits.slice(1)}`;
        if (digits.length === 10) return `+234${digits}`;
      } else if (c === 'MX') {
        if (digits.startsWith('52') && digits.length >= 12) return `+${digits}`;
        if (digits.length === 10) return `+52${digits}`;
      } else if (c === 'CA' || c === 'US') {
        if (digits.startsWith('1') && digits.length === 11) return `+${digits}`;
        if (digits.length === 10) return `+1${digits}`;
      }
      return trimmed.startsWith('+') ? trimmed : `+${digits}`;
    }

    if (c === 'NG') return `+23480${Math.floor(10000000 + Math.random() * 90000000)}`;
    if (c === 'MX') return `+5255${Math.floor(10000000 + Math.random() * 90000000)}`;
    return `+1415555${Math.floor(1000 + Math.random() * 9000)}`;
  }

  // Shared 409-conflict recovery:
  // When POST /v1/users reports 409 (User already exists), BMONI docs require:
  // "The earlier attempt landed. Recover the existing user instead of retrying."
  // Checks error payload details, registered user registry, PostgreSQL DB,
  // in-memory cache, and fallback API probe.
  static async recoverBmoniUserIdOnConflict(email: string, error?: any): Promise<string | undefined> {
    const cleanEmail = email.trim().toLowerCase();

    // 1. Check error details directly if BMONI returned the existing userId in the 409 body
    const details = error?.details || error?.responseJson;
    if (details) {
      const directId =
        details.bmoniUserId ||
        details.userId ||
        details.id ||
        details.user?.bmoniUserId ||
        details.user?.id;
      if (directId && typeof directId === 'string') {
        console.log(`[EmployeeService] Recovered BMONI user ${directId} directly from 409 error details for ${email}`);
        return directId;
      }
    }

    // 2. Check local registered users (auth system)
    try {
      const regUser = await findUserByQuery(cleanEmail);
      if (regUser) {
        const userId = regUser.bmoniUserId || regUser.userId;
        if (userId && !userId.startsWith('usr_flowpay_sandbox_') && !userId.startsWith('flowpay_')) {
          console.log(`[EmployeeService] Recovered existing BMONI user ${userId} from user registry for ${email}`);
          return userId;
        }
      }
    } catch (_) { }

    // 3. Check existing employee records in PostgreSQL
    if (isPostgresDb()) {
      try {
        const existingEmp = await prisma.employee.findFirst({
          where: {
            email: { equals: cleanEmail, mode: 'insensitive' },
            bmoniUserId: { not: null },
          },
        });
        if (existingEmp?.bmoniUserId) {
          console.log(`[EmployeeService] Recovered existing BMONI user ${existingEmp.bmoniUserId} from employee DB for ${email}`);
          return existingEmp.bmoniUserId;
        }

        const existingUser = await prisma.user.findFirst({
          where: {
            email: { equals: cleanEmail, mode: 'insensitive' },
            bmoniUserId: { not: null },
          },
        });
        if (existingUser?.bmoniUserId) {
          console.log(`[EmployeeService] Recovered existing BMONI user ${existingUser.bmoniUserId} from user DB for ${email}`);
          return existingUser.bmoniUserId;
        }
      } catch (dbErr) {
        console.warn('[EmployeeService] DB lookup error during 409 recovery:', dbErr);
      }
    }

    // 4. Check in-memory employees fallback store
    for (const emp of inMemoryEmployees.values()) {
      if (emp.email?.toLowerCase() === cleanEmail && emp.bmoniUserId) {
        console.log(`[EmployeeService] Recovered existing BMONI user ${emp.bmoniUserId} from in-memory employees for ${email}`);
        return emp.bmoniUserId;
      }
    }

    // 5. Fallback: try querying BMONI API if endpoint exists
    try {
      const listRes = await (bmoniClient as any).request('/v1/users') as {
        users?: Array<{ id: string; bmoniUserId?: string; email: string; phoneNumber?: string }>;
      };
      const matched = listRes?.users?.find(
        (u) => u.email?.toLowerCase() === cleanEmail
      );
      if (matched) {
        const recoveredId = matched.bmoniUserId || matched.id;
        console.log(`[EmployeeService] Recovered existing BMONI user ${recoveredId} on 409 conflict API lookup for ${email}`);
        return recoveredId;
      }
    } catch (recoverErr) {
      console.warn('[EmployeeService] API query fallback notice on 409:', (recoverErr as any)?.message || recoverErr);
    }

    return undefined;
  }
  static async listEmployees(statusFilter?: string): Promise<EmployeeRecord[]> {
    let dbRows: EmployeeRecord[] = [];
    if (isPostgresDb()) {
      try {
        dbRows = await prisma.employee.findMany({
          where: statusFilter ? { status: statusFilter.toUpperCase() } : undefined,
          orderBy: { createdAt: 'desc' },
        });
      } catch (err) {
        console.warn('[EmployeeService] listEmployees DB error, falling back:', err);
      }
    }

    // Merge in any employees whose create/update fell back to in-memory
    // storage (e.g. a transient DB error for just that one record) so they
    // don't silently disappear from the list just because other employees
    // exist in Postgres. DB rows win on id collision since they're the
    // more authoritative source once a write there succeeds.
    const byId = new Map<string, EmployeeRecord>();
    for (const emp of inMemoryEmployees.values()) {
      byId.set((emp as any).id, emp as EmployeeRecord);
    }
    for (const row of dbRows) {
      byId.set((row as any).id, row);
    }

    let all = Array.from(byId.values());
    if (statusFilter) {
      all = all.filter((e) => (e as any).status?.toUpperCase() === statusFilter.toUpperCase());
    }
    all.sort((a: any, b: any) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
    return all;
  }

  static async getEmployeeById(id: string): Promise<EmployeeRecord | undefined> {
    if (isPostgresDb()) {
      try {
        const row = await prisma.employee.findUnique({ where: { id } });
        if (row) return row;
      } catch (err) {
        console.warn('[EmployeeService] getEmployeeById DB error, falling back:', err);
      }
    }
    return (inMemoryEmployees.get(id) || undefined) as EmployeeRecord | undefined;
  }

  static generateInviteToken(): string {
    return crypto.randomBytes(24).toString('hex');
  }

  static async createEmployee(data: CreateEmployeeInput): Promise<{
    employee: EmployeeRecord;
    bmoniUserId?: string;
    inviteToken: string;
    inviteCode: string;
    inviteUrl: string;
    failureReason?: string;
  }> {
    const validation = this.validateCreateInput(data);
    if (!validation.valid) { const error = new Error(validation.errors.join('; ')) as Error & { statusCode?: number; errors?: string[] }; error.statusCode = 400; error.errors = validation.errors; throw error; }
    const country = data.country.trim().toUpperCase();
    const targetCurrency = data.targetCurrency?.toUpperCase() || this.resolveCurrency(country);
    const payrollCurrency = data.payrollCurrency?.toUpperCase() || targetCurrency;
    const id = `emp_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    let bmoniUserId: string | undefined;
    let createError: unknown;
    let failureReason: string | undefined;

    // BMONI requires a phone number for user creation; format or generate a valid sandbox phone
    const effectivePhone = this.buildEffectivePhone(data.phoneNumber, country);

    // Fail fast with a clear reason if the key is obviously misconfigured,
    // rather than making a doomed round trip that returns an opaque 401.
    if (bmoniClient.isApiKeyLikelyMisconfigured()) {
      console.error(
        '[EmployeeService] BMONI_API_KEY appears to be a placeholder/invalid. ' +
        'POST /v1/users will 401. Set a real BMONI_API_KEY (pk_...).'
      );
    }

    try {
      const user = await bmoniClient.createEmployeeUser({
        firstName: data.firstName.trim(),
        lastName: data.lastName.trim(),
        email: data.email.trim().toLowerCase(),
        phoneNumber: effectivePhone,
      });
      bmoniUserId = user.bmoniUserId || user.id;
      if (!bmoniUserId) {
        throw new Error('BMONI returned a 2xx response but no user ID was present in the body.');
      }
    } catch (err: any) {
      const status = err?.statusCode ?? err?.status;

      // 409 = a user already exists with this email/phone. Per BMONI docs this
      // is "success from a previous attempt" — recover rather than duplicating.
      if (status === 409) {
        console.warn(
          `[EmployeeService] BMONI reported 409 (user already exists) for ${data.email}. Attempting recovery.`
        );
        console.log('[DEBUG] Full 409 error details:', JSON.stringify(err?.details ?? err));
        const recoveredId = await this.recoverBmoniUserIdOnConflict(data.email, err);
        if (recoveredId) {
          bmoniUserId = recoveredId;
          // Recovery succeeded — leave createError unset so the rest of
          // createEmployee proceeds down the normal success path (status
          // INVITED, invite email dispatched, etc.)
        } else {
          failureReason =
            'A BMONI user already exists with this email or phone number, but the existing user could not be located to recover automatically. Use a different email/phone, or recover manually.';
          createError = err;
        }
      } else {
        const msg = err?.message || 'BMONI user creation failed';
        failureReason =
          status === 401
            ? `BMONI rejected the request (401 Unauthorized). The BMONI_API_KEY is missing, wrong for this environment, or revoked. (${msg})`
            : `BMONI user creation failed${status ? ` (HTTP ${status})` : ''}: ${msg}`;
        console.error('[EmployeeService] Failed to create BMONI user for employee:', failureReason);
        createError = err;
      }
    }

    const inviteToken = this.generateInviteToken();
    const expiresAt = new Date(Date.now() + 72 * 60 * 60 * 1000); // 72 hours single-use TTL
    const baseUrl = env.APP_URL.replace(/\/$/, '');
    const inviteUrl = `${baseUrl}/invite/${inviteToken}`;

    const employeeData = {
      id,
      bmoniUserId: bmoniUserId || null,
      partnerId: env.BMONI_PARTNER_ID,
      businessId: data.businessId || 'biz_flowpay_technologies',
      firstName: data.firstName.trim(),
      lastName: data.lastName.trim(),
      email: data.email.trim().toLowerCase(),
      phoneNumber: effectivePhone,
      country,
      targetCurrency,
      payrollAmountMinor: data.payrollAmountMinor,
      payrollCurrency,
      status: bmoniUserId ? 'INVITED' : 'FAILED',
      failedStage: bmoniUserId ? null : 'BMONI_USER_CREATION',
      walletId: null,
      walletAddress: null,
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    let employee: EmployeeRecord;
    if (isPostgresDb()) {
      try {
        employee = await prisma.employee.create({ data: employeeData as any });
      } catch (dbErr: any) {
        console.warn('[EmployeeService] DB create failed, falling back to inMemory:', dbErr?.message || dbErr);
        employee = employeeData as unknown as EmployeeRecord;
      }
    } else {
      employee = employeeData as unknown as EmployeeRecord;
    }
    inMemoryEmployees.set(id, employee);

    // Register active invite record
    const inviteRecord: EmployeeInviteRecord = {
      token: inviteToken,
      employeeId: id,
      bmoniUserId: employeeData.bmoniUserId || undefined,
      email: employeeData.email,
      firstName: employeeData.firstName,
      lastName: employeeData.lastName,
      country: employeeData.country,
      targetCurrency: employeeData.targetCurrency,
      payrollAmountMinor: employeeData.payrollAmountMinor,
      expiresAt,
    };
    employeeInvites.set(inviteToken, inviteRecord);

    // NOTE: previously this threw here whenever BMONI user creation failed.
    // The employee + invite records above are already committed (DB or
    // in-memory) by this point, so throwing discarded a real, already-saved
    // record from the API response: the app's "Add Employee" call would
    // receive a 5xx with no inviteUrl/employee payload, so nothing appeared
    // to happen even though a FAILED-status employee now existed server-side.
    // Instead, surface the failure as part of a normal (still 201) response
    // so the app can render the employee with its real FAILED status/badge
    // and let the person retry, consistent with how every other onboarding
    // stage failure in this codebase is handled.
    if (createError) {
      console.warn(
        `[EmployeeService] Employee ${id} created with status FAILED (BMONI_USER_CREATION):`,
        createError instanceof Error ? createError.message : createError
      );
    }

    // Dispatch the branded invitation email only when the BMONI user was
    // actually created. Emailing an invite for a FAILED employee is misleading
    // because the onboarding link cannot resolve to a real user yet.
    if (!createError) {
      mailService
        .sendEmployeeInvite({
          to: employeeData.email,
          recipientName: `${employeeData.firstName} ${employeeData.lastName}`.trim(),
          employerName: data.employerName || data.companyName || 'FlowPay Technologies Ltd',
          companyName: data.companyName || 'FlowPay Technologies Ltd',
          country: employeeData.country,
          currency: employeeData.payrollCurrency || undefined,
          payrollAmount: (employeeData.payrollAmountMinor / 100).toFixed(2),
          inviteUrl,
        })
        .then((res) => {
          if (res.success) {
            console.log(`[EmployeeService] ✅ Invite email successfully dispatched to ${employeeData.email} (ID: ${res.messageId})`);
          } else {
            console.warn(`[EmployeeService] ⚠️ Invite email delivery notification for ${employeeData.email}:`, res.error);
          }
        })
        .catch((err: any) => {
          console.warn('[EmployeeService] Failed to dispatch employee invite email:', err?.message || err);
        });
    }

    return {
      employee,
      bmoniUserId,
      inviteToken,
      inviteCode: inviteToken,
      inviteUrl,
      failureReason,
    };
  }

  /**
   * Re-attempt BMONI user creation for an employee stuck at status=FAILED /
   * failed_stage=BMONI_USER_CREATION (e.g. added while the API key was
   * misconfigured). Reuses the stored details; on success flips the record to
   * INVITED with the new bmoniUserId. Idempotent to call multiple times.
   */
  static async retryBmoniUserCreation(employeeId: string): Promise<EmployeeRecord> {
    const employee = await this.getEmployeeById(employeeId);
    if (!employee) {
      const err = new Error(`Employee ${employeeId} not found`) as Error & { statusCode?: number };
      err.statusCode = 404;
      throw err;
    }

    if (employee.bmoniUserId) {
      return employee; // Already has an identity — nothing to retry here.
    }

    if (bmoniClient.isApiKeyLikelyMisconfigured()) {
      const err = new Error(
        'Cannot retry: BMONI_API_KEY is still a placeholder/invalid. Set a real key (pk_...) and redeploy first.'
      ) as Error & { statusCode?: number };
      err.statusCode = 503;
      throw err;
    }

    const effectivePhone = this.buildEffectivePhone(employee.phoneNumber, employee.country);

    let bmoniUserId: string | undefined;
    try {
      const user = await bmoniClient.createEmployeeUser({
        firstName: employee.firstName.trim(),
        lastName: employee.lastName.trim(),
        email: employee.email.trim().toLowerCase(),
        phoneNumber: effectivePhone,
      });
      bmoniUserId = user.bmoniUserId || user.id;
      if (!bmoniUserId) {
        throw new Error('BMONI returned a 2xx response but no user ID was present in the body.');
      }
    } catch (err: any) {
      const status = err?.statusCode ?? err?.status;

      // 409 = a user already exists with this email/phone. Per BMONI docs,
      // recover the existing user identity rather than failing the retry.
      if (status === 409) {
        bmoniUserId = await this.recoverBmoniUserIdOnConflict(employee.email, err);
      }

      if (!bmoniUserId) {
        const msg = err?.message || 'BMONI user creation failed';
        const reason =
          status === 401
            ? `BMONI rejected the request (401 Unauthorized) — check BMONI_API_KEY. (${msg})`
            : status === 409
              ? `A BMONI user already exists with this email or phone. Use a different email/phone. (${msg})`
              : `BMONI user creation failed${status ? ` (HTTP ${status})` : ''}: ${msg}`;
        const wrapped = new Error(reason) as Error & { statusCode?: number };
        wrapped.statusCode = status || 502;
        throw wrapped;
      }
    }

    const updateData: Record<string, any> = {
      bmoniUserId: bmoniUserId || null,
      phoneNumber: employee.phoneNumber || effectivePhone,
      status: 'INVITED',
      failedStage: null,
      updatedAt: new Date(),
    };

    let updated: EmployeeRecord | undefined;
    if (isPostgresDb()) {
      try {
        updated = await prisma.employee.update({ where: { id: employeeId }, data: updateData });
      } catch (dbErr: any) {
        console.warn('[EmployeeService] retry DB update failed, updating in-memory:', dbErr?.message || dbErr);
      }
    }
    const merged = { ...(inMemoryEmployees.get(employeeId) || employee), ...updateData } as EmployeeRecord;
    const finalEmployee = (updated || merged) as EmployeeRecord;
    inMemoryEmployees.set(employeeId, finalEmployee);

    // Unlike createEmployee, a retry can happen long after the original
    // invite token was generated (and that token only ever lived in the
    // in-memory employeeInvites map, so it may no longer exist after a
    // redeploy). Generate a fresh one so the invite email actually has a
    // resolvable link, the same way createEmployee does on first success.
    const inviteToken = this.generateInviteToken();
    const baseUrl = env.APP_URL.replace(/\/$/, '');
    const inviteUrl = `${baseUrl}/invite/${inviteToken}`;
    employeeInvites.set(inviteToken, {
      token: inviteToken,
      employeeId: finalEmployee.id,
      bmoniUserId: bmoniUserId || undefined,
      email: finalEmployee.email,
      firstName: finalEmployee.firstName,
      lastName: finalEmployee.lastName,
      country: finalEmployee.country,
      targetCurrency: finalEmployee.targetCurrency,
      payrollAmountMinor: finalEmployee.payrollAmountMinor,
      expiresAt: new Date(Date.now() + 72 * 60 * 60 * 1000),
    });

    mailService
      .sendEmployeeInvite({
        to: finalEmployee.email,
        recipientName: `${finalEmployee.firstName} ${finalEmployee.lastName}`.trim(),
        employerName: 'FlowPay Technologies Ltd',
        companyName: 'FlowPay Technologies Ltd',
        country: finalEmployee.country,
        currency: finalEmployee.payrollCurrency || undefined,
        payrollAmount: (finalEmployee.payrollAmountMinor / 100).toFixed(2),
        inviteUrl,
      })
      .then((res) => {
        if (res.success) {
          console.log(`[EmployeeService] ✅ Retry invite email dispatched to ${finalEmployee.email} (ID: ${res.messageId})`);
        } else {
          console.warn(`[EmployeeService] ⚠️ Retry invite email delivery notification for ${finalEmployee.email}:`, res.error);
        }
      })
      .catch((err: any) => {
        console.warn('[EmployeeService] Failed to dispatch retry invite email:', err?.message || err);
      });

    return finalEmployee;
  }

  static async getInviteDetails(codeOrId: string): Promise<EmployeeInviteRecord> {
    const trimmed = (codeOrId || '').trim();
    // Normalize if flowpay_ prefix is attached
    const tokenOrId = trimmed.startsWith('flowpay_') ? trimmed.substring(8) : trimmed;

    // 1. Check direct token in memory
    let invite = employeeInvites.get(tokenOrId);

    // 2. Check if searching by employeeId in memory
    if (!invite) {
      for (const rec of employeeInvites.values()) {
        if (rec.employeeId === tokenOrId || rec.token === tokenOrId) {
          invite = rec;
          break;
        }
      }
    }

    // 3. Fallback: check database for employee record if restarted
    if (!invite) {
      let dbEmployee: EmployeeRecord | undefined;
      if (isPostgresDb()) {
        try {
          dbEmployee = await prisma.employee.findFirst({
            where: { OR: [{ id: tokenOrId }, { email: tokenOrId }] },
          }) ?? undefined;
        } catch (_) { }
      }
      if (!dbEmployee) {
        dbEmployee = inMemoryEmployees.get(tokenOrId) as EmployeeRecord | undefined;
        if (!dbEmployee) {
          for (const emp of inMemoryEmployees.values()) {
            if (emp.email?.toLowerCase() === tokenOrId.toLowerCase() || emp.id === tokenOrId) {
              dbEmployee = emp;
              break;
            }
          }
        }
      }

      if (dbEmployee) {
        if (['READY', 'LINKED', 'ACTIVE'].includes(dbEmployee.status?.toUpperCase())) {
          const err = new Error('This invitation has already been used and employee wallet is linked.') as Error & { statusCode?: number; code?: string };
          err.statusCode = 410;
          err.code = 'ALREADY_USED';
          throw err;
        }

        if (dbEmployee.status === 'FAILED') {
          const err = new Error('Employee onboarding is currently paused because identity creation failed. Please ask your employer to retry from the dashboard.') as Error & { statusCode?: number; code?: string };
          err.statusCode = 400;
          err.code = 'EMPLOYEE_CREATION_FAILED';
          throw err;
        }

        if (dbEmployee.status === 'INVITED') {
          const fallbackToken = this.generateInviteToken();
          invite = {
            token: fallbackToken,
            employeeId: dbEmployee.id,
            bmoniUserId: dbEmployee.bmoniUserId || undefined,
            email: dbEmployee.email,
            firstName: dbEmployee.firstName,
            lastName: dbEmployee.lastName,
            country: dbEmployee.country,
            targetCurrency: dbEmployee.targetCurrency,
            payrollAmountMinor: dbEmployee.payrollAmountMinor,
            expiresAt: new Date(Date.now() + 72 * 60 * 60 * 1000),
          };
          employeeInvites.set(fallbackToken, invite);
        }
      }
    }

    if (!invite) {
      const err = new Error(`Invitation "${codeOrId}" was not found or is invalid.`) as Error & { statusCode?: number; code?: string };
      err.statusCode = 404;
      err.code = 'NOT_FOUND';
      throw err;
    }

    // 4. Validate single-use status
    if (invite.usedAt) {
      const err = new Error('This invitation has already been used and employee wallet is linked.') as Error & { statusCode?: number; code?: string };
      err.statusCode = 410;
      err.code = 'ALREADY_USED';
      throw err;
    }

    // 5. Validate expiration
    if (new Date() > invite.expiresAt) {
      const err = new Error('This invitation has expired. Please request a new invite from your employer.') as Error & { statusCode?: number; code?: string };
      err.statusCode = 410;
      err.code = 'EXPIRED';
      throw err;
    }

    return invite;
  }

  static async linkEmployeeWallet(input: LinkEmployeeWalletInput): Promise<EmployeeRecord> {
    if (!input.requestingUserId && !input.requestingEmail) {
      const err = new Error('Authentication required: valid employee session required to link wallet.') as Error & { statusCode?: number; code?: string };
      err.statusCode = 401;
      err.code = 'UNAUTHORIZED';
      throw err;
    }

    // 1. Resolve and validate invite token (unexpired & unused)
    const invite = await this.getInviteDetails(input.inviteToken);

    // 2. Verify requesting session matches invited employee
    const reqUser = (input.requestingUserId || '').trim();
    const reqEmail = (input.requestingEmail || '').trim().toLowerCase();
    const targetEmail = invite.email.toLowerCase();

    let isMatch = false;

    // Direct email match if passed in session
    if (reqEmail && reqEmail === targetEmail) {
      isMatch = true;
    }

    // Pre-provisioned BMONI identity match on the invited employee
    if (invite.bmoniUserId && reqUser && reqUser === invite.bmoniUserId) {
      isMatch = true;
    }

    // Match employee ID
    if (reqUser && reqUser === invite.employeeId) {
      isMatch = true;
    }

    // Match registered user email in DB if Postgres is active, or in-memory registry
    if (!isMatch && reqUser) {
      if (isPostgresDb()) {
        try {
          const dbUser = await prisma.user.findFirst({
            where: { OR: [{ id: reqUser }, { bmoniUserId: reqUser }] },
          });
          if (dbUser && dbUser.email.toLowerCase() === targetEmail) {
            isMatch = true;
          }
        } catch (_) { }
      }
      if (!isMatch) {
        try {
          const inMemUser = await findUserByQuery(reqUser);
          if (inMemUser && inMemUser.email.toLowerCase() === targetEmail) {
            isMatch = true;
          }
        } catch (_) { }
      }
    }

    if (!isMatch) {
      const err = new Error('Forbidden: Your authenticated session does not match the invited employee record.') as Error & { statusCode?: number; code?: string };
      err.statusCode = 403;
      err.code = 'FORBIDDEN';
      throw err;
    }

    // 3. Mark invite as used (single-use enforcement)
    invite.usedAt = new Date();
    employeeInvites.set(invite.token, invite);

    // 4. Update employee record to READY with employee's own hardware wallet
    const updateData = {
      bmoniUserId: input.bmoniUserId,
      walletAddress: input.walletAddress,
      walletId: input.walletId || null,
      status: 'READY',
      failedStage: null,
      updatedAt: new Date(),
    };

    let updated: EmployeeRecord | undefined;
    if (isPostgresDb()) {
      try {
        updated = await prisma.employee.update({
          where: { id: invite.employeeId },
          data: updateData,
        });
      } catch (err) {
        console.warn('[EmployeeService] linkEmployeeWallet DB update error:', err);
      }
    }

    const existingInMemory = inMemoryEmployees.get(invite.employeeId) || {};
    updated = {
      ...existingInMemory,
      ...updateData,
      id: invite.employeeId,
      email: invite.email,
      firstName: invite.firstName,
      lastName: invite.lastName,
      country: invite.country,
      targetCurrency: invite.targetCurrency,
      payrollAmountMinor: invite.payrollAmountMinor,
    } as EmployeeRecord;

    inMemoryEmployees.set(invite.employeeId, updated);
    return updated;
  }

  static async updateEmployeeStatus(id: string, status: EmployeeLifecycleStage | string, failedStage?: string): Promise<EmployeeRecord | undefined> {
    if (isPostgresDb()) {
      try { return await prisma.employee.update({ where: { id }, data: { status: status.toUpperCase(), failedStage: failedStage || null } }); }
      catch (err) { console.warn('[EmployeeService] updateEmployeeStatus error:', err); return undefined; }
    }
    const emp = inMemoryEmployees.get(id);
    if (emp) {
      emp.status = status.toUpperCase();
      emp.failedStage = failedStage || null;
      inMemoryEmployees.set(id, emp);
      return emp as EmployeeRecord;
    }
    return undefined;
  }

  static async inviteEmployee(data: {
    firstName: string;
    lastName: string;
    email: string;
    phoneNumber?: string;
    country: string;
    targetCurrency?: string;
    payrollAmount?: number;
    employerName?: string;
    companyName?: string;
  }): Promise<{ employee: EmployeeRecord; inviteUrl: string; inviteToken: string; inviteCode: string }> {
    const result = await this.createEmployee({
      ...data,
      payrollAmountMinor: data.payrollAmount || 100000,
    });

    return {
      employee: result.employee,
      inviteUrl: result.inviteUrl,
      inviteToken: result.inviteToken,
      inviteCode: result.inviteCode,
    };
  }
}

