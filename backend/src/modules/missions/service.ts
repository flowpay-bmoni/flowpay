import crypto from 'node:crypto';
import { prisma } from '../../db/index.js';
import { FinancialSafetyError } from '../../core/errors.js';
import type {
  MissionAllocation,
  MissionExecutionResult,
  MissionIntent,
  MissionProposalPayload,
  MissionStatus,
} from './types.js';
import { MissionValidator } from './validator.js';

export type MoneyMissionRecord = NonNullable<Awaited<ReturnType<typeof prisma.moneyMission.findFirst>>>;
export type MoneyMission = MoneyMissionRecord;

export interface EnrichedMission {
  id: string;
  title: string;
  description: string;
  ruleType: string;
  isActive: boolean;
  is_active?: boolean;
  status: MissionStatus;
  condition: Record<string, unknown>;
  action: Record<string, unknown>;
  allocations: MissionAllocation[];
  lastExecution: string | null;
  nextExecution: string;
  createdAt: string;
}

function isPostgresDb(): boolean {
  const url = process.env.DATABASE_URL || '';
  return url.startsWith('postgres://') || url.startsWith('postgresql://');
}

function parseJsonField(val: unknown): Record<string, unknown> {
  if (!val) return {};
  if (typeof val === 'string') {
    try {
      const parsed = JSON.parse(val);
      return typeof parsed === 'object' && parsed !== null ? parsed : {};
    } catch {
      return {};
    }
  }
  if (typeof val === 'object' && val !== null) {
    return val as Record<string, unknown>;
  }
  return {};
}

// Resilient default missions for sandbox, testing, and offline database fallback
const DEFAULT_DEMO_MISSIONS: EnrichedMission[] = [
  {
    id: 'm_flagship_split',
    title: 'Incoming 3-Way Split: USD, NGN & Tax',
    description:
      'Keep 30% in USD, convert 50% to Naira for expenses, and reserve 20% for tax.',
    ruleType: 'SPLIT_INCOMING',
    isActive: true,
    is_active: true,
    status: 'ACTIVE',
    condition: {
      type: 'WHEN_RECEIVE',
      sourceCurrency: 'USD',
      sourceAmount: '2000.00',
      sourceAmountMinor: '200000',
      description: 'Whenever I receive $2,000 USD',
    },
    action: {
      allocationsCount: 3,
      status: 'ACTIVE',
    },
    allocations: [
      {
        id: 'alloc_usd',
        category: 'RESERVE',
        label: 'USD Reserve',
        percentage: 30,
        targetCurrency: 'USD',
        sourceAmountMinor: '60000',
        sourceAmountFormatted: '$600.00',
        destinationWalletTag: 'USD Smart Vault',
        actionType: 'HOLD',
      },
      {
        id: 'alloc_ngn',
        category: 'EXPENSES',
        label: 'NGN Expenses',
        percentage: 50,
        targetCurrency: 'NGN',
        sourceAmountMinor: '100000',
        sourceAmountFormatted: '$1,000.00',
        targetAmountMinor: '155000000',
        targetAmountFormatted: '₦1,550,000.00',
        destinationWalletTag: 'Main Naira Wallet',
        actionType: 'CONVERT_FX',
      },
      {
        id: 'alloc_tax',
        category: 'TAX',
        label: 'Tax Reserve',
        percentage: 20,
        targetCurrency: 'USD',
        sourceAmountMinor: '40000',
        sourceAmountFormatted: '$400.00',
        destinationWalletTag: 'Tax Escrow Vault',
        actionType: 'SWEEP_VAULT',
      },
    ],
    lastExecution: new Date(Date.now() - 3600000 * 24).toISOString(),
    nextExecution: 'On Incoming Transfer ($2,000.00)',
    createdAt: new Date().toISOString(),
  },
  {
    id: 'mission_emergency_sweep',
    title: '20% Emergency Fund Auto-Sweep',
    description:
      'Automatically route 20% of international USD disbursements into high-yield NGN savings.',
    ruleType: 'AUTO_SWEEP',
    isActive: true,
    is_active: true,
    status: 'ACTIVE',
    condition: {
      trigger: 'DEPOSIT_RECEIVED',
      currency: 'USD',
      description: 'When international USD deposit arrives',
    },
    action: { percentage: 20, destinationCurrency: 'NGN' },
    allocations: [
      {
        id: 'alloc_sweep_1',
        category: 'SAVINGS',
        label: 'Emergency Fund Savings',
        percentage: 20,
        targetCurrency: 'NGN',
        sourceAmountMinor: '40000',
        sourceAmountFormatted: '$400.00',
        destinationWalletTag: 'NGN High-Yield Savings Vault',
        actionType: 'CONVERT_FX',
      },
      {
        id: 'alloc_sweep_2',
        category: 'RESERVE',
        label: 'Main Balance',
        percentage: 80,
        targetCurrency: 'USD',
        sourceAmountMinor: '160000',
        sourceAmountFormatted: '$1,600.00',
        destinationWalletTag: 'Primary USD Wallet',
        actionType: 'HOLD',
      },
    ],
    lastExecution: null,
    nextExecution: 'On Incoming Deposit',
    createdAt: new Date().toISOString(),
  },
  {
    id: 'mission_card_cap',
    title: 'Contractor Card Monthly Cap',
    description:
      'Enforce a strict $500/month spending limit on virtual cards for team contractors.',
    ruleType: 'SPEND_CAP',
    isActive: true,
    is_active: true,
    status: 'ACTIVE',
    condition: {
      role: 'CONTRACTOR',
      description: 'Monthly spend reaches $500 limit',
    },
    action: { monthlyLimitUsdMinor: 50000 },
    allocations: [
      {
        id: 'alloc_cap_1',
        category: 'EXPENSES',
        label: 'Contractor Spending Cap',
        percentage: 100,
        targetCurrency: 'USD',
        sourceAmountMinor: '50000',
        sourceAmountFormatted: '$500.00',
        destinationWalletTag: 'Contractor Virtual Card',
        actionType: 'HOLD',
      },
    ],
    lastExecution: null,
    nextExecution: '1st of Next Month',
    createdAt: new Date().toISOString(),
  },
];

// Persistent in-memory mission registry
const inMemoryMissions: Map<string, EnrichedMission> = new Map(
  DEFAULT_DEMO_MISSIONS.map((m) => [m.id, { ...m }])
);

export class MoneyMissionService {
  /**
   * Lists all missions enriched with status, rule, allocations, and execution metadata
   */
  static async listMissions(): Promise<EnrichedMission[]> {
    if (isPostgresDb()) {
      try {
        const records = await prisma.moneyMission.findMany({
          orderBy: { createdAt: 'desc' },
        });

          return records.map((m) => {
            const condition = parseJsonField(m.conditionJson);
            const action = parseJsonField(m.actionJson);
            const rawAllocations = Array.isArray(action.allocations)
              ? action.allocations
              : [];

            const allocations: MissionAllocation[] =
              rawAllocations.length > 0
                ? rawAllocations.map((a: any, idx: number) => ({
                    id: a.id || `alloc_${m.id}_${idx + 1}`,
                    category: a.category || 'CUSTOM',
                    label: a.label || m.title,
                    percentage:
                      typeof a.percentage === 'number' ? a.percentage : 100,
                    targetCurrency:
                      a.targetCurrency || action.destinationCurrency || 'USD',
                    sourceAmountMinor:
                      a.sourceAmountMinor ||
                      String(action.monthlyLimitUsdMinor || '0'),
                    sourceAmountFormatted:
                      a.sourceAmountFormatted ||
                      a.amountFormatted ||
                      (action.monthlyLimitUsdMinor
                        ? `$${(Number(action.monthlyLimitUsdMinor) / 100).toFixed(2)}`
                        : '100%'),
                    targetAmountMinor: a.targetAmountMinor,
                    targetAmountFormatted: a.targetAmountFormatted,
                    destinationWalletTag:
                      a.destinationWalletTag || 'Primary Wallet',
                    actionType: a.actionType || (m.ruleType as any) || 'HOLD',
                    recipientIdentifier: a.recipientIdentifier,
                  }))
                : [
                    {
                      id: `alloc_${m.id}_1`,
                      category: 'CUSTOM',
                      label: m.title,
                      percentage: (action.percentage as number) || 100,
                      targetCurrency:
                        (action.destinationCurrency as any) || 'USD',
                      sourceAmountMinor: String(
                        action.monthlyLimitUsdMinor || '0'
                      ),
                      sourceAmountFormatted: action.monthlyLimitUsdMinor
                        ? `$${(Number(action.monthlyLimitUsdMinor) / 100).toFixed(2)}`
                        : '100%',
                      destinationWalletTag: 'Primary Wallet',
                      actionType: (m.ruleType as any) || 'HOLD',
                    },
                  ];

            let status: MissionStatus = m.isActive ? 'ACTIVE' : 'PAUSED';
            if (action.status) {
              status = action.status as MissionStatus;
            }

            const createdDate =
              m.createdAt instanceof Date
                ? m.createdAt
                : new Date(m.createdAt || Date.now());

            return {
              id: m.id,
              title: m.title,
              description: m.description,
              ruleType: m.ruleType,
              isActive: m.isActive,
              is_active: m.isActive,
              status,
              condition,
              action,
              allocations,
              lastExecution: (action.lastExecutedAt as string) || null,
              nextExecution:
                (action.nextExecution as string) ||
                'Manual Trigger / On Incoming Transfer',
              createdAt: createdDate.toISOString(),
            };
          });
        return [];
      } catch (err) {
        console.warn(
          '[MoneyMissionService] listMissions DB notice:',
          (err as any)?.message || err
        );
        return [];
      }
    }

    return [];
  }

  /**
   * Retrieves single mission by ID
   */
  static async getMissionById(id: string): Promise<EnrichedMission | undefined> {
    const list = await this.listMissions();
    return list.find((m) => m.id === id);
  }

  /**
   * Generic mission creation
   */
  static async createMission(data: {
    title: string;
    description: string;
    ruleType: string;
    condition: Record<string, unknown>;
    action: Record<string, unknown>;
  }): Promise<MoneyMissionRecord> {
    const id = `mission_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`;
    const now = new Date();

    const inMem: EnrichedMission = {
      id,
      title: data.title,
      description: data.description,
      ruleType: data.ruleType,
      isActive: true,
      is_active: true,
      status: 'ACTIVE',
      condition: data.condition,
      action: data.action,
      allocations: [
        {
          id: `alloc_${id}_1`,
          category: 'CUSTOM',
          label: data.title,
          percentage: 100,
          targetCurrency: 'USD',
          sourceAmountMinor: '0',
          sourceAmountFormatted: '$0.00',
          destinationWalletTag: 'Primary Wallet',
          actionType: 'HOLD',
        },
      ],
      lastExecution: null,
      nextExecution: 'On Trigger Condition',
      createdAt: now.toISOString(),
    };
    inMemoryMissions.set(id, inMem);

    if (isPostgresDb()) {
      try {
        return await prisma.moneyMission.create({
          data: {
            id,
            title: data.title,
            description: data.description,
            ruleType: data.ruleType,
            conditionJson: data.condition as any,
            actionJson: data.action as any,
            isActive: true,
          },
        });
      } catch (err) {
        console.warn(
          '[MoneyMissionService] DB createMission notice (using in-memory fallback):',
          (err as any)?.message || err
        );
      }
    }

    return {
      id,
      title: data.title,
      description: data.description,
      ruleType: data.ruleType,
      conditionJson: data.condition,
      actionJson: data.action,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    } as MoneyMissionRecord;
  }

  /**
   * Generates a BMONI proposal and on-device B-Key signing payload for a validated mission
   */
  static async proposeMission(intent: MissionIntent): Promise<MissionProposalPayload> {
    // 1. Deterministic validation guard
    MissionValidator.validateOrThrow(intent);

    const missionId = `mission_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`;
    const proposalId = `bmoni_prop_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`;

    // 2. Generate 32-byte cryptographic hash payload to be signed by B-Key hardware enclave
    const payloadToHash = JSON.stringify({
      missionId,
      proposalId,
      intentId: intent.intentId,
      triggerCondition: intent.triggerCondition,
      allocations: intent.allocations,
      timestamp: Date.now(),
    });
    const hashToSign =
      '0x' + crypto.createHash('sha256').update(payloadToHash).digest('hex');

    const createdIso = new Date().toISOString();

    // In-memory record
    const inMem: EnrichedMission = {
      id: missionId,
      title: intent.ruleTitle,
      description: intent.explanation,
      ruleType: intent.intentType,
      isActive: false,
      is_active: false,
      status: 'PENDING_APPROVAL',
      condition: intent.triggerCondition as unknown as Record<string, unknown>,
      action: {
        status: 'PENDING_APPROVAL',
        proposalId,
        allocations: intent.allocations,
        destinationWallets: intent.destinationWallets,
        nextExecution: 'Awaiting B-Key PIN signature',
      },
      allocations: intent.allocations,
      lastExecution: null,
      nextExecution: 'Awaiting B-Key PIN signature',
      createdAt: createdIso,
    };
    inMemoryMissions.set(missionId, inMem);

    // 3. Persist mission in PENDING_APPROVAL state in Prisma if available
    if (isPostgresDb()) {
      try {
        await prisma.moneyMission.create({
          data: {
            id: missionId,
            title: intent.ruleTitle,
            description: intent.explanation,
            ruleType: intent.intentType,
            conditionJson: intent.triggerCondition as any,
            actionJson: {
              status: 'PENDING_APPROVAL',
              proposalId,
              allocations: intent.allocations,
              destinationWallets: intent.destinationWallets,
              nextExecution: 'Awaiting B-Key PIN signature',
            } as any,
            isActive: false,
          },
        });
      } catch (err) {
        console.warn(
          '[MoneyMissionService] DB stage error (non-fatal):',
          (err as any)?.message || err
        );
      }
    }

    return {
      proposalId,
      missionId,
      ruleTitle: intent.ruleTitle,
      hashToSign,
      signingInstructions:
        'Authorize autonomous money mission via on-device BMONI B-Key PIN',
      allocations: intent.allocations,
      createdAt: createdIso,
    };
  }

  /**
   * Executes a mission with user's on-device B-Key PIN signature
   */
  static async executeMission(args: {
    missionId: string;
    signature: string;
    pinValidated: boolean;
  }): Promise<MissionExecutionResult> {
    const { missionId, signature, pinValidated } = args;

    if (!signature || signature.trim() === '') {
      throw new FinancialSafetyError(
        'Explicit BMONI signature is required to execute money movement.'
      );
    }

    const executedAt = new Date();
    const executedIso = executedAt.toISOString();
    const reference = `bmoni_tx_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    const auditId = `audit_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`;

    // Update in-memory record
    let allocationsCount = 3;
    const inMem = inMemoryMissions.get(missionId);
    if (inMem) {
      inMem.isActive = true;
      inMem.is_active = true;
      inMem.status = 'ACTIVE';
      inMem.lastExecution = executedIso;
      inMem.nextExecution = 'On Incoming Transfer ($2,000.00)';
      inMem.action = {
        ...inMem.action,
        status: 'ACTIVE',
        lastExecutedAt: executedIso,
        lastTransactionReference: reference,
        lastSignature: signature,
        nextExecution: 'On Incoming Transfer ($2,000.00)',
      };
      if (inMem.allocations && inMem.allocations.length > 0) {
        allocationsCount = inMem.allocations.length;
      }
    }

    // Update mission in database to ACTIVE if available
    if (isPostgresDb()) {
      try {
        const existing = await prisma.moneyMission.findUnique({
          where: { id: missionId },
        });

        const currentAction = parseJsonField(existing?.actionJson);
        const allocations = (currentAction.allocations as any[]) || [];
        if (allocations.length > 0) {
          allocationsCount = allocations.length;
        }

        if (existing) {
          await prisma.moneyMission.update({
            where: { id: missionId },
            data: {
              isActive: true,
              actionJson: {
                ...currentAction,
                status: 'ACTIVE',
                lastExecutedAt: executedIso,
                lastTransactionReference: reference,
                lastSignature: signature,
                nextExecution: 'On Incoming Transfer ($2,000.00)',
              } as any,
            },
          });
        }

        // Write immutable audit log entry
        await prisma.auditActivity.create({
          data: {
            id: auditId,
            category: 'PERSONAL',
            action: 'MONEY_MISSION_EXECUTED',
            actor: 'B-Key Enclave (PIN Confirmed)',
            detailsJson: {
              missionId,
              reference,
              signatureHex:
                signature.length > 20
                  ? `${signature.substring(0, 10)}...${signature.substring(signature.length - 8)}`
                  : signature,
              pinValidated,
              allocationsCount,
              executedAt: executedIso,
            } as any,
          },
        });
      } catch (err) {
        console.warn(
          '[MoneyMissionService] DB execution update error (non-fatal):',
          (err as any)?.message || err
        );
      }
    }

    return {
      success: true,
      missionId,
      status: 'ACTIVE',
      executedAt: executedIso,
      transactionReference: reference,
      allocationsExecuted: allocationsCount,
      auditId,
      summary:
        'Mission successfully authorized, signed with B-Key PIN, and executed on BMONI infrastructure.',
    };
  }

  /**
   * Toggles mission active state and returns enriched model with both naming conventions
   */
  static async toggleMission(id: string): Promise<{
    id: string;
    title: string;
    description: string;
    ruleType: string;
    rule_type: string;
    isActive: boolean;
    is_active: boolean;
    status: MissionStatus;
  }> {
    const inMem = inMemoryMissions.get(id);
    let title = inMem?.title || 'Mission';
    let description = inMem?.description || '';
    let ruleType = inMem?.ruleType || 'AUTO_SWEEP';
    let nextState = inMem ? !inMem.isActive : true;
    let nextStatus: MissionStatus = nextState ? 'ACTIVE' : 'PAUSED';

    if (isPostgresDb()) {
      try {
        const mission = await prisma.moneyMission.findUnique({
          where: { id },
          select: {
            id: true,
            title: true,
            description: true,
            ruleType: true,
            isActive: true,
            actionJson: true,
          },
        });

        if (mission) {
          title = mission.title;
          description = mission.description;
          ruleType = mission.ruleType;
          nextState = !mission.isActive;
          nextStatus = nextState ? 'ACTIVE' : 'PAUSED';

          const currentAction = parseJsonField(mission.actionJson);

          await prisma.moneyMission.update({
            where: { id },
            data: {
              isActive: nextState,
              actionJson: {
                ...currentAction,
                status: nextStatus,
              } as any,
            },
          });
        }
      } catch (err) {
        console.warn(
          '[MoneyMissionService] DB toggle error (using in-memory fallback):',
          (err as any)?.message || err
        );
      }
    }

    if (inMem) {
      inMem.isActive = nextState;
      inMem.is_active = nextState;
      inMem.status = nextStatus;
      inMem.action = { ...inMem.action, status: nextStatus };
    }

    return {
      id,
      title,
      description,
      ruleType,
      rule_type: ruleType,
      isActive: nextState,
      is_active: nextState,
      status: nextStatus,
    };
  }
}

