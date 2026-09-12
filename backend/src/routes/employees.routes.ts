import { Router } from 'express';
import { EmployeeService } from '../modules/employees/service.js';
import { EmployeeOnboardingService } from '../modules/employees/onboarding.service.js';

export const employeesRouter = Router();

import { parsePaginationParams, paginateArray } from '../core/pagination.js';

// GET /api/employees?status=READY&country=NG&search=Bunch&page=1&limit=10
employeesRouter.get('/', async (req, res, next) => {
  try {
    const status = req.query.status as string | undefined;
    const country = req.query.country as string | undefined;
    const search = req.query.search as string | undefined;
    let list = await EmployeeService.listEmployees(status);

    if (country && country !== 'ALL') {
      list = list.filter(
        (e: any) => e.country?.toUpperCase() === country.toUpperCase()
      );
    }

    if (search) {
      const q = search.toLowerCase();
      list = list.filter(
        (e: any) =>
          e.firstName?.toLowerCase().includes(q) ||
          e.lastName?.toLowerCase().includes(q) ||
          e.email?.toLowerCase().includes(q) ||
          e.country?.toLowerCase().includes(q) ||
          e.countryName?.toLowerCase().includes(q)
      );
    }

    const enrichEmployee = (emp: any) => {
      if (!emp) return emp;
      return {
        ...emp,
        failureReason: emp.failedStage
          ? emp.failedStage === 'BMONI_USER_CREATION'
            ? 'BMONI user creation failed'
            : `Failed during Stage ${emp.failedStage} processing`
          : emp.failureReason || null,
      };
    };

    list = list.map(enrichEmployee);

    if (req.query.page !== undefined || req.query.limit !== undefined) {
      const { page, limit } = parsePaginationParams(req.query, 10);
      const paginated = paginateArray(list, page, limit);
      return res.json({ success: true, data: paginated });
    }

    res.json({ success: true, data: list });
  } catch (err) {
    next(err);
  }
});
// GET /api/employees/status/:status
employeesRouter.get('/status/:status', async (req, res, next) => {
  try {
    const list = await EmployeeService.listEmployees(req.params.status);
    const enriched = list.map((emp: any) => ({
      ...emp,
      failureReason: emp.failedStage
        ? emp.failedStage === 'BMONI_USER_CREATION'
          ? 'BMONI user creation failed'
          : `Failed during Stage ${emp.failedStage} processing`
        : emp.failureReason || null,
    }));
    res.json({ success: true, data: enriched });
  } catch (err) {
    next(err);
  }
});

// GET /api/employees/:id
employeesRouter.get('/:id', async (req, res, next) => {
  try {
    const employee = await EmployeeService.getEmployeeById(req.params.id);
    if (!employee) {
      return res.status(404).json({ success: false, message: 'Employee not found' });
    }
    const enriched = {
      ...employee,
      failureReason: employee.failedStage
        ? employee.failedStage === 'BMONI_USER_CREATION'
          ? 'BMONI user creation failed'
          : `Failed during Stage ${employee.failedStage} processing`
        : (employee as any).failureReason || null,
    };
    res.json({ success: true, data: enriched });
  } catch (err) {
    next(err);
  }
});

// POST /api/employees - Primary employee creation endpoint with server-side validation
employeesRouter.post('/', async (req, res, next) => {
  try {
    const {
      firstName,
      lastName,
      email,
      phoneNumber,
      country,
      targetCurrency,
      payrollAmountMinor,
      payrollCurrency,
      employerName,
      companyName,
      businessId,
    } = req.body;

    // Handle either payrollAmountMinor directly or payrollAmount in major
    let amountMinor: number | undefined;
    if (payrollAmountMinor !== undefined) {
      amountMinor = typeof payrollAmountMinor === 'string'
        ? parseInt(payrollAmountMinor, 10)
        : Number(payrollAmountMinor);
    } else if (req.body.payrollAmount !== undefined) {
      amountMinor = Number.isInteger(req.body.payrollAmount)
        ? req.body.payrollAmount
        : Math.round(Number(req.body.payrollAmount) * 100);
    } else if (req.body.salary !== undefined) {
      amountMinor = Math.round(Number(req.body.salary) * 100);
    }

    const result = await EmployeeService.createEmployee({
      firstName,
      lastName,
      email,
      phoneNumber,
      country,
      targetCurrency,
      payrollAmountMinor: amountMinor ?? 0,
      payrollCurrency,
      employerName,
      companyName,
      businessId,
    });

    res.status(201).json({
      success: true,
      message: result.bmoniUserId
        ? 'Employee created successfully with BMONI on-chain identity'
        : 'Employee record created, but BMONI on-chain identity creation failed. Employee is saved with status FAILED and can be retried.',
      data: result,
    });
  } catch (err: any) {
    if (err.statusCode === 400 || err.errors) {
      return res.status(400).json({
        success: false,
        message: err.message,
        errors: err.errors || [err.message],
      });
    }
    next(err);
  }
});

// POST /api/employees/invite - Backward compatibility alias
employeesRouter.post('/invite', async (req, res, next) => {
  try {
    const result = await EmployeeService.inviteEmployee(req.body);
    res.json({ success: true, data: result });
  } catch (err: any) {
    if (err.statusCode === 400 || err.errors) {
      return res.status(400).json({
        success: false,
        message: err.message,
        errors: err.errors,
      });
    }
    next(err);
  }
});

// GET /api/employees/invite/:codeOrId - Resolve invite token details for employee self-onboarding
employeesRouter.get('/invite/:codeOrId', async (req, res, next) => {
  try {
    const invite = await EmployeeService.getInviteDetails(req.params.codeOrId);

    if (req.headers.accept?.includes('text/html')) {
      const salaryFormatted = (invite.payrollAmountMinor / 100).toLocaleString('en-US', {
        style: 'currency',
        currency: invite.targetCurrency || 'USD',
      });
      return res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>FlowPay - Accept Payroll Invitation</title>
  <style>
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #0b0f19; color: #f3f4f6; display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 20px; box-sizing: border-box; }
    .card { background: #111827; border: 1px solid #1f2937; border-radius: 16px; max-width: 480px; width: 100%; padding: 32px; box-shadow: 0 10px 25px -5px rgba(0,0,0,0.5); text-align: center; }
    .badge { display: inline-block; background: rgba(16, 185, 129, 0.15); color: #10b981; border: 1px solid rgba(16, 185, 129, 0.3); border-radius: 20px; padding: 4px 12px; font-size: 12px; font-weight: 600; margin-bottom: 16px; letter-spacing: 0.5px; }
    h1 { font-size: 22px; margin: 0 0 10px 0; color: #ffffff; }
    p.subtitle { color: #9ca3af; font-size: 14px; margin: 0 0 24px 0; line-height: 20px; }
    .details { background: #1f2937; border-radius: 12px; padding: 18px; margin-bottom: 24px; text-align: left; }
    .row { display: flex; justify-content: space-between; margin-bottom: 10px; font-size: 14px; }
    .row:last-child { margin-bottom: 0; }
    .label { color: #9ca3af; }
    .value { color: #ffffff; font-weight: 600; }
    .code-box { background: #0b0f19; border: 1px dashed #374151; border-radius: 8px; padding: 12px; font-family: monospace; font-size: 16px; color: #818cf8; word-break: break-all; margin-bottom: 24px; user-select: all; }
    .btn { display: block; width: 100%; box-sizing: border-box; background: linear-gradient(135deg, #10b981 0%, #059669 100%); color: #ffffff; text-decoration: none; font-size: 15px; font-weight: 600; padding: 14px 20px; border-radius: 8px; border: none; cursor: pointer; transition: opacity 0.2s; }
    .btn:hover { opacity: 0.9; }
    .note { margin-top: 16px; font-size: 12px; color: #6b7280; }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">SECURE INVITATION</div>
    <h1>FlowPay Global Payroll</h1>
    <p class="subtitle">You have been invited to set up your self-custody payout wallet and complete KYC verification.</p>
    <div class="details">
      <div class="row"><span class="label">Recipient:</span><span class="value">${invite.firstName} ${invite.lastName}</span></div>
      <div class="row"><span class="label">Country / Rail:</span><span class="value">${invite.country} (${invite.targetCurrency})</span></div>
      <div class="row"><span class="label">Payroll Amount:</span><span class="value">${salaryFormatted}</span></div>
      <div class="row"><span class="label">Status:</span><span class="value" style="color:#10b981;">Active Invitation</span></div>
    </div>
    <div style="font-size: 12px; color: #9ca3af; margin-bottom: 6px; text-align: left;">Your Single-Use Invite Token:</div>
    <div class="code-box">${invite.token}</div>
    <a href="flowpay://invite/${invite.token}" class="btn">Open in FlowPay Mobile App</a>
    <div class="note">Open this link in the FlowPay mobile app to generate your smart contract wallet with local hardware PIN encryption.</div>
  </div>
</body>
</html>`);
    }

    res.json({ success: true, data: invite });
  } catch (err: any) {
    if (err.statusCode) {
      if (req.headers.accept?.includes('text/html')) {
        return res.status(err.statusCode).send(`<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Invitation Expired - FlowPay</title><style>body { margin: 0; font-family: sans-serif; background: #0b0f19; color: #fff; display: flex; align-items: center; justify-content: center; min-height: 100vh; } .card { background: #111827; padding: 32px; border-radius: 16px; border: 1px solid #1f2937; text-align: center; max-width: 400px; }</style></head>
<body><div class="card"><h2 style="color:#ef4444;">Invitation Invalid or Expired</h2><p style="color:#9ca3af;font-size:14px;">${err.message}</p></div></body></html>`);
      }
      return res.status(err.statusCode).json({
        success: false,
        code: err.code || 'INVITE_ERROR',
        message: err.message,
      });
    }
    next(err);
  }
});

// POST /api/employees/link-wallet - Link employee's self-custody wallet created on their own device
employeesRouter.post('/link-wallet', async (req, res, next) => {
  try {
    const { employeeId, inviteToken, bmoniUserId, walletAddress, walletId } = req.body;

    // Resolve requesting user from session header (x-user-id or Authorization bearer)
    const headerUserId = req.headers['x-user-id'] as string | undefined;
    const authHeader = req.headers.authorization;
    let requestingUserId = headerUserId;

    if (!requestingUserId && authHeader?.startsWith('Bearer ')) {
      const bearer = authHeader.substring(7);
      const match = bearer.match(/^flowpay_jwt_(usr_[a-zA-Z0-9_-]+)/);
      requestingUserId = match ? match[1] : bearer;
    }

    if (!requestingUserId && req.body.requestingUserId) {
      requestingUserId = req.body.requestingUserId;
    }

    const requestingEmail = (req.headers['x-user-email'] as string | undefined) || req.body.requestingEmail;

    if (!inviteToken) {
      return res.status(400).json({ success: false, message: 'inviteToken is required' });
    }
    if (!walletAddress) {
      return res.status(400).json({ success: false, message: 'walletAddress is required' });
    }
    if (!bmoniUserId) {
      return res.status(400).json({ success: false, message: 'bmoniUserId is required' });
    }

    const updated = await EmployeeService.linkEmployeeWallet({
      employeeId,
      inviteToken,
      bmoniUserId,
      walletAddress,
      walletId,
      requestingUserId,
      requestingEmail,
    });

    res.json({
      success: true,
      message: 'Employee wallet linked successfully and ready for payroll',
      data: updated,
    });
  } catch (err: any) {
    if (err.statusCode) {
      return res.status(err.statusCode).json({
        success: false,
        code: err.code || 'LINK_ERROR',
        message: err.message,
      });
    }
    next(err);
  }
});


// PATCH /api/employees/:id/status - Update lifecycle stage
employeesRouter.patch('/:id/status', async (req, res, next) => {
  try {
    const { status, failedStage } = req.body;
    if (!status) {
      return res.status(400).json({ success: false, message: 'status is required' });
    }

    const updated = await EmployeeService.updateEmployeeStatus(req.params.id, status, failedStage);
    if (!updated) {
      return res.status(404).json({ success: false, message: 'Employee not found' });
    }

    res.json({ success: true, data: updated });
  } catch (err) {
    next(err);
  }
});

// POST /api/employees/:id/retry-user-creation - Re-attempt BMONI user creation
// for an employee stuck at FAILED / BMONI_USER_CREATION (e.g. added while the
// API key was misconfigured). Safe to call repeatedly.
employeesRouter.post('/:id/retry-user-creation', async (req, res, next) => {
  try {
    const updated = await EmployeeService.retryBmoniUserCreation(req.params.id);
    res.json({
      success: true,
      message: updated.bmoniUserId
        ? 'BMONI identity created. Employee is now INVITED and ready to onboard.'
        : 'Retry completed but no BMONI identity was returned.',
      data: updated,
    });
  } catch (err: any) {
    if (err.statusCode) {
      return res.status(err.statusCode).json({
        success: false,
        code: err.code || 'RETRY_FAILED',
        message: err.message,
      });
    }
    next(err);
  }
});

// =========================================================================
// BMONI MULTI-STAGE ONBOARDING ENDPOINTS (Stages 2, 3, 4)
// =========================================================================

// POST /api/employees/:id/onboarding/challenge - Stage 2: Request Owner Proof Challenge
employeesRouter.post('/:id/onboarding/challenge', async (req, res, next) => {
  try {
    const { userOwnerAddress } = req.body;
    const challenge = await EmployeeOnboardingService.requestOwnerChallenge(req.params.id, userOwnerAddress);
    res.json({ success: true, data: challenge });
  } catch (err) {
    next(err);
  }
});

// POST /api/employees/:id/onboarding/wallet - Stage 2: Deploy Managed Smart Wallet
employeesRouter.post('/:id/onboarding/wallet', async (req, res, next) => {
  try {
    const { userOwnerAddress, ownerProofChallengeId, ownerProofSignature } = req.body;
    const result = await EmployeeOnboardingService.provisionSmartWallet(req.params.id, {
      userOwnerAddress,
      ownerProofChallengeId,
      ownerProofSignature,
    });
    res.json({ success: true, data: result });
  } catch (err) {
    next(err);
  }
});

// GET /api/employees/:id/onboarding/kyc/options - Stage 3: Get KYC options
employeesRouter.get('/:id/onboarding/kyc/options', async (req, res, next) => {
  try {
    const options = await EmployeeOnboardingService.getKycOptions(req.params.id);
    res.json({ success: true, data: options });
  } catch (err) {
    next(err);
  }
});

// POST /api/employees/:id/onboarding/kyc/submit - Stage 3: Submit Country-Specific KYC
employeesRouter.post('/:id/onboarding/kyc/submit', async (req, res, next) => {
  try {
    const result = await EmployeeOnboardingService.submitCountryKyc(req.params.id, req.body);
    res.json({ success: true, data: result });
  } catch (err) {
    next(err);
  }
});

// GET /api/employees/:id/onboarding/kyc/readiness - Stage 3: Check readiness gate
employeesRouter.get('/:id/onboarding/kyc/readiness', async (req, res, next) => {
  try {
    const readiness = await EmployeeOnboardingService.checkKycReadiness(req.params.id);
    res.json({ success: true, data: readiness });
  } catch (err) {
    next(err);
  }
});

// POST /api/employees/:id/onboarding/kyc/activate - Stage 3: Activate KYC
employeesRouter.post('/:id/onboarding/kyc/activate', async (req, res, next) => {
  try {
    const result = await EmployeeOnboardingService.activateKyc(req.params.id);
    res.json({ success: true, data: result });
  } catch (err) {
    next(err);
  }
});

// GET /api/employees/:id/onboarding/mx/agreements - Stage 4 (Mexico): Fetch Etherfuse agreements
employeesRouter.get('/:id/onboarding/mx/agreements', async (req, res, next) => {
  try {
    const agreements = await EmployeeOnboardingService.getMexicoAgreements(req.params.id);
    res.json({ success: true, data: agreements });
  } catch (err) {
    next(err);
  }
});

// POST /api/employees/:id/onboarding/activate-rail - Stage 4: Activate Country Rail
employeesRouter.post('/:id/onboarding/activate-rail', async (req, res, next) => {
  try {
    const result = await EmployeeOnboardingService.activateRail(req.params.id, req.body);
    res.json({ success: true, data: result });
  } catch (err) {
    next(err);
  }
});

// GET /api/employees/:id/onboarding/status - Aggregate status across stages 2/3/4
employeesRouter.get('/:id/onboarding/status', async (req, res, next) => {
  try {
    const status = await EmployeeOnboardingService.getOnboardingStatus(req.params.id);
    res.json({ success: true, data: status });
  } catch (err) {
    next(err);
  }
});

// POST /api/employees/:id/onboarding/retry - Retry failed or pending stage
employeesRouter.post('/:id/onboarding/retry', async (req, res, next) => {
  try {
    const status = await EmployeeOnboardingService.retryStage(req.params.id);
    res.json({ success: true, data: status });
  } catch (err) {
    next(err);
  }
});

// POST /api/employees/:id/onboarding/simulate-complete - Sandbox webhook completion simulation
employeesRouter.post('/:id/onboarding/simulate-complete', async (req, res, next) => {
  try {
    const status = await EmployeeOnboardingService.simulateOnboardingCompleted(req.params.id);
    res.json({ success: true, data: status });
  } catch (err) {
    next(err);
  }
});
