import { describe, it } from 'node:test';
import assert from 'node:assert';
import { EmployeeService } from './service.js';

describe('Employee Management Validation & Lifecycle', () => {
  it('validates a valid Nigerian employee creation payload', () => {
    const result = EmployeeService.validateCreateInput({
      firstName: 'Bunch',
      lastName: 'Dillon',
      email: 'bunch.dillon@example.ng',
      country: 'NG',
      payrollAmountMinor: 310000000, // 3,100,000 NGN in kobo
    });

    assert.strictEqual(result.valid, true);
    assert.strictEqual(result.errors.length, 0);
  });

  it('validates a valid Mexican employee creation payload', () => {
    const result = EmployeeService.validateCreateInput({
      firstName: 'Samson',
      lastName: 'Jabo',
      email: 'samson.jabo@example.mx',
      country: 'MX',
      payrollAmountMinor: 3500000, // 35,000 MXN in centavos
    });

    assert.strictEqual(result.valid, true);
    assert.strictEqual(result.errors.length, 0);
  });

  it('rejects invalid email formats', () => {
    const result = EmployeeService.validateCreateInput({
      firstName: 'Test',
      lastName: 'User',
      email: 'invalid-email-no-domain',
      country: 'NG',
      payrollAmountMinor: 100000,
    });

    assert.strictEqual(result.valid, false);
    assert.ok(result.errors.some((e) => e.includes('valid email')));
  });

  it('rejects missing or empty names', () => {
    const result = EmployeeService.validateCreateInput({
      firstName: '',
      lastName: '   ',
      email: 'test@example.com',
      country: 'NG',
      payrollAmountMinor: 100000,
    });

    assert.strictEqual(result.valid, false);
    assert.ok(result.errors.some((e) => e.includes('firstName')));
    assert.ok(result.errors.some((e) => e.includes('lastName')));
  });

  it('rejects unsupported countries', () => {
    const result = EmployeeService.validateCreateInput({
      firstName: 'Test',
      lastName: 'User',
      email: 'test@example.com',
      country: 'XX',
      payrollAmountMinor: 100000,
    });

    assert.strictEqual(result.valid, false);
    assert.ok(result.errors.some((e) => e.includes('country must be one of')));
  });

  it('rejects non-positive or non-integer payroll amounts', () => {
    const zeroResult = EmployeeService.validateCreateInput({
      firstName: 'Test',
      lastName: 'User',
      email: 'test@example.com',
      country: 'NG',
      payrollAmountMinor: 0,
    });
    assert.strictEqual(zeroResult.valid, false);

    const negativeResult = EmployeeService.validateCreateInput({
      firstName: 'Test',
      lastName: 'User',
      email: 'test@example.com',
      country: 'NG',
      payrollAmountMinor: -5000,
    });
    assert.strictEqual(negativeResult.valid, false);

    const floatResult = EmployeeService.validateCreateInput({
      firstName: 'Test',
      lastName: 'User',
      email: 'test@example.com',
      country: 'NG',
      payrollAmountMinor: 123.45 as any,
    });
    assert.strictEqual(floatResult.valid, false);
  });

  it('resolves correct settlement currency for countries', () => {
    assert.strictEqual(EmployeeService.resolveCurrency('NG'), 'NGN');
    assert.strictEqual(EmployeeService.resolveCurrency('MX'), 'MXN');
    assert.strictEqual(EmployeeService.resolveCurrency('CA'), 'CAD');
    assert.strictEqual(EmployeeService.resolveCurrency('US'), 'USD');
  });

  it('returns status FAILED with null bmoniUserId when BMONI user creation fails', async () => {
    const { bmoniClient } = await import('../../bmoni/client.js');
    const { prisma, isPostgresDb } = await import('../../db/index.js');

    const originalCreate = bmoniClient.createEmployeeUser;
    bmoniClient.createEmployeeUser = async () => {
      throw new Error('BMONI connection timeout (504)');
    };

    let createdRecordId: string | undefined;
    try {
      const result = await EmployeeService.createEmployee({
        firstName: 'TestFail',
        lastName: 'User',
        email: 'fail-test@example.com',
        country: 'NG',
        payrollAmountMinor: 100000,
      });

      assert.strictEqual(result.employee.status, 'FAILED');
      assert.strictEqual(result.employee.failedStage, 'BMONI_USER_CREATION');
      assert.strictEqual(result.bmoniUserId, undefined);
      assert.strictEqual(result.employee.bmoniUserId, null, 'Must never assign a fake bmoniUserId');
      assert.ok(result.failureReason, 'Must include failureReason');

      if (isPostgresDb()) {
        const record = await prisma.employee.findFirst({
          where: { email: 'fail-test@example.com' },
        });
        assert.ok(record, 'Employee record should be persisted for audit tracking');
        createdRecordId = record.id;
        assert.strictEqual(record.status, 'FAILED');
        assert.strictEqual(record.failedStage, 'BMONI_USER_CREATION');
        assert.strictEqual(record.bmoniUserId, null, 'Must never assign a fake bmoniUserId');
      }
    } finally {
      bmoniClient.createEmployeeUser = originalCreate;
      if (createdRecordId && isPostgresDb()) {
        await prisma.employee.delete({ where: { id: createdRecordId } }).catch(() => {});
      }
    }
  });

  it('succeeds and records real bmoniUserId with status INVITED and single-use inviteToken', async () => {
    const { bmoniClient } = await import('../../bmoni/client.js');
    const { prisma, isPostgresDb } = await import('../../db/index.js');

    const originalCreate = bmoniClient.createEmployeeUser;
    bmoniClient.createEmployeeUser = async () => {
      return {
        id: 'usr_real_bmoni_99999',
        bmoniUserId: 'usr_real_bmoni_99999',
        firstName: 'TestSuccess',
        lastName: 'User',
        email: 'success-test@example.com',
        partnerId: 'part_flowpay_01',
        createdAt: new Date().toISOString(),
      };
    };

    let createdRecordId: string | undefined;
    try {
      const result = await EmployeeService.createEmployee({
        firstName: 'TestSuccess',
        lastName: 'User',
        email: 'success-test@example.com',
        country: 'NG',
        payrollAmountMinor: 100000,
      });

      assert.strictEqual(result.bmoniUserId, 'usr_real_bmoni_99999');
      assert.strictEqual(result.employee.status, 'INVITED');
      assert.strictEqual(result.employee.bmoniUserId, 'usr_real_bmoni_99999');
      assert.ok(result.inviteToken, 'Must generate single-use inviteToken');
      assert.ok(result.inviteUrl, 'Must generate inviteUrl');
      createdRecordId = result.employee.id;
    } finally {
      bmoniClient.createEmployeeUser = originalCreate;
      if (createdRecordId && isPostgresDb()) {
        await prisma.employee.delete({ where: { id: createdRecordId } }).catch(() => {});
      }
    }
  });

  describe('Employee Invite-Then-Self-Onboard Wallet Linkage', () => {
    it('links wallet with valid token and matching employee session -> transitions status to READY', async () => {
      const { bmoniClient } = await import('../../bmoni/client.js');
      const originalCreate = bmoniClient.createEmployeeUser;
      bmoniClient.createEmployeeUser = async () => ({
        id: 'usr_emp_onboard_1',
        bmoniUserId: 'usr_emp_onboard_1',
        firstName: 'Amara',
        lastName: 'Okonkwo',
        email: 'amara.okonkwo@flowpay.ng',
        partnerId: 'part_flowpay_01',
        createdAt: new Date().toISOString(),
      });

      try {
        const invite = await EmployeeService.createEmployee({
          firstName: 'Amara',
          lastName: 'Okonkwo',
          email: 'amara.okonkwo@flowpay.ng',
          country: 'NG',
          payrollAmountMinor: 310000000,
        });

        assert.strictEqual(invite.employee.status, 'INVITED');
        assert.ok(invite.inviteToken);

        // Fetch invite details
        const details = await EmployeeService.getInviteDetails(invite.inviteToken);
        assert.strictEqual(details.email, 'amara.okonkwo@flowpay.ng');

        // Employee self-onboards on own device, receives own session
        const employeeSessionUserId = 'usr_emp_onboard_1';
        const hardwareWalletAddress = '0x1234567890abcdef1234567890abcdef12345678';

        const linked = await EmployeeService.linkEmployeeWallet({
          employeeId: invite.employee.id,
          inviteToken: invite.inviteToken,
          bmoniUserId: employeeSessionUserId,
          walletAddress: hardwareWalletAddress,
          requestingUserId: employeeSessionUserId,
        });

        assert.strictEqual(linked.status, 'READY');
        assert.strictEqual(linked.walletAddress, hardwareWalletAddress);
        assert.strictEqual(linked.bmoniUserId, employeeSessionUserId);
      } finally {
        bmoniClient.createEmployeeUser = originalCreate;
      }
    });

    it('rejects link-wallet attempt with wrong/foreign session', async () => {
      const { bmoniClient } = await import('../../bmoni/client.js');
      const originalCreate = bmoniClient.createEmployeeUser;
      bmoniClient.createEmployeeUser = async () => ({
        id: 'usr_emp_onboard_2',
        bmoniUserId: 'usr_emp_onboard_2',
        firstName: 'Chidi',
        lastName: 'Eze',
        email: 'chidi.eze@flowpay.ng',
        partnerId: 'part_flowpay_01',
        createdAt: new Date().toISOString(),
      });

      try {
        const invite = await EmployeeService.createEmployee({
          firstName: 'Chidi',
          lastName: 'Eze',
          email: 'chidi.eze@flowpay.ng',
          country: 'NG',
          payrollAmountMinor: 150000000,
        });

        // An unauthorized employer or malicious third party tries to claim the wallet
        const foreignSessionId = 'usr_foreign_attacker_or_employer';

        await assert.rejects(
          async () => {
            await EmployeeService.linkEmployeeWallet({
              employeeId: invite.employee.id,
              inviteToken: invite.inviteToken,
              bmoniUserId: 'usr_foreign_attacker_or_employer',
              walletAddress: '0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
              requestingUserId: foreignSessionId,
            });
          },
          (err: any) => {
            return err.statusCode === 403 && err.code === 'FORBIDDEN';
          },
          'Must reject wallet linking with foreign session token'
        );
      } finally {
        bmoniClient.createEmployeeUser = originalCreate;
      }
    });

    it('rejects link-wallet attempt with expired invite token', async () => {
      const { employeeInvites } = await import('./service.js');
      const expiredToken = 'token_already_expired_123';
      employeeInvites.set(expiredToken, {
        token: expiredToken,
        employeeId: 'emp_expired_test',
        email: 'expired.worker@flowpay.test',
        firstName: 'Expired',
        lastName: 'Worker',
        country: 'NG',
        targetCurrency: 'NGN',
        payrollAmountMinor: 1000000,
        expiresAt: new Date(Date.now() - 3600000), // expired 1 hour ago
      });

      await assert.rejects(
        async () => {
          await EmployeeService.linkEmployeeWallet({
            inviteToken: expiredToken,
            bmoniUserId: 'usr_emp_expired',
            walletAddress: '0x1234567890abcdef1234567890abcdef12345678',
            requestingUserId: 'usr_emp_expired',
          });
        },
        (err: any) => {
          return err.statusCode === 410 && err.code === 'EXPIRED';
        },
        'Must reject expired invite tokens with 410 EXPIRED'
      );
    });

    it('rejects link-wallet attempt when invite token is used twice (single-use enforcement)', async () => {
      const { bmoniClient } = await import('../../bmoni/client.js');
      const originalCreate = bmoniClient.createEmployeeUser;
      bmoniClient.createEmployeeUser = async () => ({
        id: 'usr_emp_onboard_single_use',
        bmoniUserId: 'usr_emp_onboard_single_use',
        firstName: 'Tolu',
        lastName: 'Ade',
        email: 'tolu.ade@flowpay.ng',
        partnerId: 'part_flowpay_01',
        createdAt: new Date().toISOString(),
      });

      try {
        const invite = await EmployeeService.createEmployee({
          firstName: 'Tolu',
          lastName: 'Ade',
          email: 'tolu.ade@flowpay.ng',
          country: 'NG',
          payrollAmountMinor: 200000000,
        });

        // 1st attempt: success
        await EmployeeService.linkEmployeeWallet({
          employeeId: invite.employee.id,
          inviteToken: invite.inviteToken,
          bmoniUserId: 'usr_emp_onboard_single_use',
          walletAddress: '0x1111111111111111111111111111111111111111',
          requestingUserId: 'usr_emp_onboard_single_use',
        });

        // 2nd attempt: must fail with ALREADY_USED
        await assert.rejects(
          async () => {
            await EmployeeService.linkEmployeeWallet({
              employeeId: invite.employee.id,
              inviteToken: invite.inviteToken,
              bmoniUserId: 'usr_emp_onboard_single_use',
              walletAddress: '0x2222222222222222222222222222222222222222',
              requestingUserId: 'usr_emp_onboard_single_use',
            });
          },
          (err: any) => {
            return err.statusCode === 410 && err.code === 'ALREADY_USED';
          },
          'Must reject re-using an invite token once linked'
        );
      } finally {
        bmoniClient.createEmployeeUser = originalCreate;
      }
    });
  });

  describe('Effective Phone Number Resolution & Deduplication', () => {
    it('preserves existing E.164 phone numbers', () => {
      assert.strictEqual(
        EmployeeService.buildEffectivePhone('+2348012345678', 'NG'),
        '+2348012345678'
      );
      assert.strictEqual(
        EmployeeService.buildEffectivePhone('+525512345678', 'MX'),
        '+525512345678'
      );
    });

    it('normalizes domestic phone numbers to valid E.164 format', () => {
      assert.strictEqual(
        EmployeeService.buildEffectivePhone('08139088072', 'NG'),
        '+2348139088072'
      );
      assert.strictEqual(
        EmployeeService.buildEffectivePhone('5512345678', 'MX'),
        '+525512345678'
      );
    });

    it('generates valid country-specific sandbox phones when null/undefined/empty', () => {
      const ngPhone = EmployeeService.buildEffectivePhone(undefined, 'NG');
      assert.ok(ngPhone.startsWith('+23480'), `Expected +23480..., got ${ngPhone}`);
      assert.strictEqual(ngPhone.length, 14);

      const mxPhone = EmployeeService.buildEffectivePhone('', 'MX');
      assert.ok(mxPhone.startsWith('+5255'), `Expected +5255..., got ${mxPhone}`);
      assert.strictEqual(mxPhone.length, 13);

      const usPhone = EmployeeService.buildEffectivePhone(null, 'US');
      assert.ok(usPhone.startsWith('+1415555'), `Expected +1415555..., got ${usPhone}`);
    });
  });

  describe('409 Conflict User Recovery & Invite Lookup Lifecycle', () => {
    it('recovers existing bmoniUserId directly from 409 error details', async () => {
      const errorWithDetails = {
        details: { bmoniUserId: 'usr_recovered_from_error_payload' },
      };
      const recovered = await EmployeeService.recoverBmoniUserIdOnConflict(
        'conflict.test@flowpay.finance',
        errorWithDetails
      );
      assert.strictEqual(recovered, 'usr_recovered_from_error_payload');
    });

    it('recovers existing bmoniUserId from in-memory employee record on conflict', async () => {
      const { inMemoryEmployees } = await import('./service.js');
      const testEmp = {
        id: 'emp_in_memory_conflict',
        email: 'inmem.conflict@flowpay.finance',
        bmoniUserId: 'usr_recovered_from_inmem',
        status: 'INVITED',
      };
      inMemoryEmployees.set(testEmp.id, testEmp);

      const recovered = await EmployeeService.recoverBmoniUserIdOnConflict(
        'inmem.conflict@flowpay.finance'
      );
      assert.strictEqual(recovered, 'usr_recovered_from_inmem');
    });

    it('returns 410 ALREADY_USED when employee was already onboarded and invite re-accessed', async () => {
      const { inMemoryEmployees } = await import('./service.js');
      const empId = `emp_already_ready_${Date.now()}`;
      inMemoryEmployees.set(empId, {
        id: empId,
        email: 'already.ready@flowpay.finance',
        firstName: 'Ready',
        lastName: 'User',
        status: 'READY',
        bmoniUserId: 'usr_already_ready_1',
      });

      await assert.rejects(
        async () => {
          await EmployeeService.getInviteDetails(empId);
        },
        (err: any) => {
          return err.statusCode === 410 && err.code === 'ALREADY_USED';
        },
        'Expected 410 ALREADY_USED for already onboarded employee'
      );
    });

    it('returns 400 EMPLOYEE_CREATION_FAILED when invite lookup hits an employee in FAILED state', async () => {
      const { inMemoryEmployees } = await import('./service.js');
      const empId = `emp_failed_stage_${Date.now()}`;
      inMemoryEmployees.set(empId, {
        id: empId,
        email: 'failed.emp@flowpay.finance',
        firstName: 'Failed',
        lastName: 'User',
        status: 'FAILED',
        failedStage: 'BMONI_USER_CREATION',
      });

      await assert.rejects(
        async () => {
          await EmployeeService.getInviteDetails(empId);
        },
        (err: any) => {
          return err.statusCode === 400 && err.code === 'EMPLOYEE_CREATION_FAILED';
        },
        'Expected 400 EMPLOYEE_CREATION_FAILED for failed employee'
      );
    });
  });

  describe('retryBmoniUserCreation Lifecycle & Invite Email Dispatch', () => {
    it('uses effective phone and dispatches employee invite email on successful retry', async () => {
      const { bmoniClient } = await import('../../bmoni/client.js');
      const { mailService } = await import('../mail/service.js');
      const { inMemoryEmployees } = await import('./service.js');

      const testEmpId = `emp_retry_test_${Date.now()}`;
      const fakeEmployee = {
        id: testEmpId,
        firstName: 'RetryFirst',
        lastName: 'RetryLast',
        email: 'retry.test@flowpay.finance',
        phoneNumber: null, // intentionally missing to test BUG A
        country: 'NG',
        targetCurrency: 'NGN',
        payrollAmountMinor: 5000000,
        payrollCurrency: 'NGN',
        status: 'FAILED',
        failedStage: 'BMONI_USER_CREATION',
        bmoniUserId: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      inMemoryEmployees.set(testEmpId, fakeEmployee);

      let capturedPhone: string | undefined;
      const originalCreate = bmoniClient.createEmployeeUser;
      bmoniClient.createEmployeeUser = async (input: any) => {
        capturedPhone = input.phoneNumber;
        return {
          id: 'usr_retry_bmoni_success',
          bmoniUserId: 'usr_retry_bmoni_success',
          firstName: input.firstName,
          lastName: input.lastName,
          email: input.email,
          partnerId: 'part_flowpay_01',
          createdAt: new Date().toISOString(),
        };
      };

      let inviteEmailSent = false;
      let inviteParams: any;
      const originalSend = mailService.sendEmployeeInvite;
      mailService.sendEmployeeInvite = async (params: any) => {
        inviteEmailSent = true;
        inviteParams = params;
        return { success: true, messageId: 'msg_test_retry_invite' };
      };

      try {
        const updated = await EmployeeService.retryBmoniUserCreation(testEmpId);

        // BUG A assertion: phone number must NOT be undefined/empty; must be generated effective phone
        assert.ok(capturedPhone, 'phoneNumber must be passed to BMONI');
        assert.ok(capturedPhone.startsWith('+23480'), 'Generated phone must match country format');

        // Verify status and bmoniUserId updated
        assert.strictEqual(updated.status, 'INVITED');
        assert.strictEqual(updated.bmoniUserId, 'usr_retry_bmoni_success');
        assert.strictEqual(updated.failedStage, null);

        // Wait small tick for non-blocking mailService call to execute
        await new Promise((r) => setTimeout(r, 50));

        // BUG B assertion: invite email must be sent
        assert.strictEqual(inviteEmailSent, true, 'sendEmployeeInvite must be called on successful retry');
        assert.strictEqual(inviteParams.to, 'retry.test@flowpay.finance');
        assert.ok(inviteParams.inviteUrl, 'inviteUrl must be provided in invite email');
      } finally {
        bmoniClient.createEmployeeUser = originalCreate;
        mailService.sendEmployeeInvite = originalSend;
      }
    });
  });
});

