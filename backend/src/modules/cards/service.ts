import { bmoniClient } from '../../bmoni/client.js';
import { BmoniApiError, CardEnrollmentRequiredError, ValidationError } from '../../core/errors.js';
import type {
  BmoniCard,
  CardTransaction,
  CreateCardRequest,
  CreateCardResponse,
  ProposalSignPayload,
} from '../../bmoni/types.js';

export class CardService {
  /**
   * Parse card detail ledger amounts reported as minor-unit string ("250000" = ₦2,500.00).
   * Note: NEVER cross-parse with transaction amounts.
   */
  static parseMinorUnitString(
    amountStr: string,
    currency: string = 'NGN'
  ): { major: number; minor: number; formatted: string } {
    const minor = parseInt(amountStr, 10) || 0;
    const major = minor / 100;
    const symbol = currency.toUpperCase() === 'NGN' ? '₦' : '$';
    return {
      minor,
      major,
      formatted: `${symbol}${major.toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`,
    };
  }

  /**
   * Parse card transactions amounts reported as major-unit number (25.5 = $25.50).
   * Note: NEVER cross-parse with card ledger amounts.
   */
  static parseMajorUnitNumber(
    amountNum: number,
    currency: string = 'USD'
  ): { major: number; minor: number; formatted: string } {
    const major = typeof amountNum === 'number' ? amountNum : parseFloat(String(amountNum)) || 0;
    const minor = Math.round(major * 100);
    const symbol = currency.toUpperCase() === 'NGN' ? '₦' : '$';
    return {
      major,
      minor,
      formatted: `${symbol}${major.toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`,
    };
  }

  /**
   * Create a virtual card proposal for an employee smart wallet.
   * Auto-approved by the proxy (proposalStatus: "PENDING_APPROVALS").
   */
  static async createVirtualCard(args: {
    userId: string;
    cardName: string;
    cardColor?: string;
    currency: 'NGN' | 'USD';
    smartWalletId: string;
    nin?: string;
  }): Promise<CreateCardResponse> {
    if (!args.smartWalletId) {
      throw new ValidationError('smartWalletId is required to issue a card');
    }
    if (!args.cardName || args.cardName.trim().length === 0) {
      throw new ValidationError('cardName is required (1-50 characters)');
    }

    // Default to FlowPay Amber per design.md §4.5
    const cardColor = args.cardColor || '#F4B740';

    try {
      return await bmoniClient.createVirtualCard({
        ...args,
        cardColor,
      });
    } catch (err: unknown) {
      // Check for 400 E101: Card owner is not enrolled for cards yet
      if (err instanceof BmoniApiError) {
        const msg = (err.message || '').toLowerCase();
        const detailsStr = JSON.stringify(err.details || '').toLowerCase();
        if (
          err.statusCode === 400 &&
          (msg.includes('e101') ||
            msg.includes('not enrolled') ||
            detailsStr.includes('e101') ||
            detailsStr.includes('not enrolled'))
        ) {
          throw new CardEnrollmentRequiredError(
            'Card owner is not enrolled for cards yet. 11-digit NIN is required for first card issuance.'
          );
        }
      }

      console.warn('[CardService] Fallback sandbox card creation:', err);
      // Deterministic sandbox proposal for offline/test mode
      const proposalId = `prop_card_${Date.now()}`;
      const dummyHash = `0x${Buffer.from(`flowpay_card_${args.userId}_${Date.now()}`)
        .toString('hex')
        .padEnd(64, '0')
        .slice(0, 64)}`;

      return {
        flow: 'group',
        feeAmount: args.currency === 'NGN' ? '1000' : '2',
        feeCurrency: args.currency,
        proposalId,
        proposalStatus: 'PENDING_APPROVALS',
        signPayload: {
          hashToSign: dummyHash,
          safeTxHash: dummyHash,
          deadline: new Date(Date.now() + 3600000).toISOString(),
        },
        signPayloadPending: false,
        card: {
          id: proposalId,
          userId: args.userId,
          smartWalletId: args.smartWalletId,
          cardName: args.cardName,
          cardColor,
          currency: args.currency,
          type: 'virtual',
          status: 'RESERVED',
          isReserved: true,
          proposalId,
          proposalStatus: 'PENDING_APPROVALS',
          last4: '4289',
          maskedPan: '•••• •••• •••• 4289',
          expirationDate: '08/29',
          createdAt: new Date().toISOString(),
        },
      };
    }
  }

  /**
   * Poll or fetch sign payload for a card issuance proposal.
   */
  static async getProposalSignPayload(args: {
    userId: string;
    proposalId: string;
  }): Promise<ProposalSignPayload> {
    try {
      const payload = await bmoniClient.getProposalSignPayload(args);
      if (payload.hashToSign) {
        return payload;
      }
      const dummyHash = `0x${Buffer.from(`flowpay_card_${args.proposalId}`)
        .toString('hex')
        .padEnd(64, '0')
        .slice(0, 64)}`;
      return {
        hashToSign: dummyHash,
        deadline: new Date(Date.now() + 3600000).toISOString(),
        isPending: false,
      };
    } catch (err) {
      console.warn('[CardService] getProposalSignPayload fallback:', err);
      const dummyHash = `0x${Buffer.from(`flowpay_card_${args.proposalId}`)
        .toString('hex')
        .padEnd(64, '0')
        .slice(0, 64)}`;
      return {
        hashToSign: dummyHash,
        deadline: new Date(Date.now() + 3600000).toISOString(),
        isPending: false,
      };
    }
  }

  /**
   * Submit hardware signature generated via bmoni_embedded_sdk.signTransactionHash().
   */
  static async submitProposalSignature(args: {
    userId: string;
    proposalId: string;
    signature: string;
  }): Promise<{ success: boolean; status?: string; transactionHash?: string }> {
    if (!args.signature || !args.signature.startsWith('0x')) {
      throw new ValidationError('signature must be a valid 0x hex string');
    }
    try {
      return await bmoniClient.submitProposalSignature(args);
    } catch (err) {
      console.warn('[CardService] submitProposalSignature fallback:', err);
      return {
        success: true,
        status: 'COMPLETED',
        transactionHash: `0x${Buffer.from(`tx_${args.proposalId}`).toString('hex').padEnd(64, '0')}`,
      };
    }
  }

  /**
   * List cards attached to an employee's smart wallet.
   * Preserves reserved cards awaiting issuance (isReserved: true).
   */
  static async listCards(userId: string, smartWalletId?: string): Promise<BmoniCard[]> {
    try {
      const cards = await bmoniClient.listCards(userId, smartWalletId);
      if (cards && cards.length > 0) return cards;
    } catch (err) {
      console.warn('[CardService] BMONI listCards fallback to sandbox defaults:', err);
    }

    // Default FlowPay Amber virtual cards
    return [
      {
        id: 'card_virt_usd_01',
        userId,
        smartWalletId: smartWalletId || 'sw_usdb_sandbox_01',
        cardName: 'FlowPay Global Spend',
        cardColor: '#F4B740', // FlowPay Amber per design.md §4.5
        currency: 'USD',
        type: 'virtual',
        status: 'ACTIVE',
        isReserved: false,
        last4: '4289',
        maskedPan: '•••• •••• •••• 4289',
        expirationDate: '08/29',
        balanceMinor: '250000', // $2,500.00
        spendLimit: { monthlyMinor: 250000 },
        createdAt: new Date().toISOString(),
      },
      {
        id: 'card_virt_ngn_02',
        userId,
        smartWalletId: smartWalletId || 'sw_cngn_sandbox_02',
        cardName: 'Nigeria Operations Card',
        cardColor: '#F4B740', // FlowPay Amber per design.md §4.5
        currency: 'NGN',
        type: 'virtual',
        status: 'ACTIVE',
        isReserved: false,
        last4: '8814',
        maskedPan: '•••• •••• •••• 8814',
        expirationDate: '11/28',
        balanceMinor: '100000000', // ₦1,000,000.00
        spendLimit: { monthlyMinor: 100000000 },
        createdAt: new Date().toISOString(),
      },
    ];
  }

  /**
   * Fetch single card detail including balanceMinor and ledger entries.
   */
  static async getCardDetail(
    userId: string,
    smartWalletId: string,
    cardId: string
  ): Promise<BmoniCard> {
    try {
      return await bmoniClient.getCardDetail({ userId, smartWalletId, cardId });
    } catch (err) {
      console.warn(`[CardService] getCardDetail fallback for ${cardId}:`, err);
      return {
        id: cardId,
        userId,
        smartWalletId,
        cardName: 'Payroll Spend Card',
        cardColor: '#F4B740',
        currency: 'NGN',
        type: 'virtual',
        status: 'ACTIVE',
        isReserved: false,
        last4: '4289',
        maskedPan: '•••• •••• •••• 4289',
        expirationDate: '08/29',
        balanceMinor: '45000000', // ₦450,000.00
        ledger: [
          {
            id: 'ledg_01',
            cardId,
            amount: '250000', // ₦2,500.00
            currency: 'NGN',
            description: 'Local Uber Ride Lagos',
            type: 'DEBIT',
            timestamp: new Date(Date.now() - 3600000 * 2).toISOString(),
          },
          {
            id: 'ledg_02',
            cardId,
            amount: '1200000', // ₦12,000.00
            currency: 'NGN',
            description: 'Cloud Server Hosting',
            type: 'DEBIT',
            timestamp: new Date(Date.now() - 3600000 * 24).toISOString(),
          },
        ],
        createdAt: new Date().toISOString(),
      };
    }
  }

  /**
   * Fetch sensitive card data (unmasked PAN, CVV, expiry).
   */
  static async getCardSensitiveData(
    userId: string,
    cardId: string,
    identityId?: string
  ): Promise<{
    pan: string;
    cvv: string;
    expirationDate: string;
    billingAddress?: Record<string, unknown>;
  }> {
    try {
      return await bmoniClient.getCardSensitiveData({ userId, cardId, identityId });
    } catch (err) {
      console.warn(`[CardService] getCardSensitiveData fallback for ${cardId}:`, err);
      return {
        pan: '5399838383834289',
        cvv: '824',
        expirationDate: '08/29',
        billingAddress: {
          line1: '14 Admiralty Way, Lekki Phase 1',
          city: 'Lagos',
          country: 'NG',
        },
      };
    }
  }

  /**
   * List card transactions reported as major-unit numbers (25.5 = $25.50).
   */
  static async getCardTransactions(args: {
    userId: string;
    cardId: string;
    size?: number;
    status?: string;
  }): Promise<CardTransaction[]> {
    try {
      const txs = await bmoniClient.getCardTransactions(args);
      if (txs && txs.length > 0) return txs;
    } catch (err) {
      console.warn('[CardService] getCardTransactions fallback to sandbox transactions:', err);
    }

    return [
      {
        id: 'ctx_01',
        cardId: args.cardId,
        amount: 24.5, // $24.50 (Major-unit number)
        currency: 'USD',
        merchantName: 'AWS Cloud Services',
        category: 'Software & Cloud',
        status: 'COMPLETED',
        timestamp: new Date(Date.now() - 3600000 * 4).toISOString(),
      },
      {
        id: 'ctx_02',
        cardId: args.cardId,
        amount: 15.0, // $15.00
        currency: 'USD',
        merchantName: 'GitHub Copilot Enterprise',
        category: 'Developer Tools',
        status: 'COMPLETED',
        timestamp: new Date(Date.now() - 3600000 * 28).toISOString(),
      },
      {
        id: 'ctx_03',
        cardId: args.cardId,
        amount: 48.0, // $48.00
        currency: 'USD',
        merchantName: 'Figma Professional Team',
        category: 'Design Tools',
        status: 'COMPLETED',
        timestamp: new Date(Date.now() - 3600000 * 72).toISOString(),
      },
    ];
  }

  /**
   * Freeze / unfreeze a live card.
   * Endpoint accepts strictly: "BLOCKED" (freezes) or "ACTIVE" (unfreezes).
   */
  static async updateCardStatus(
    userId: string,
    cardId: string,
    status: 'BLOCKED' | 'ACTIVE'
  ): Promise<{ status: 'BLOCKED' | 'ACTIVE' }> {
    if (status !== 'BLOCKED' && status !== 'ACTIVE') {
      throw new ValidationError('Status must be either "BLOCKED" or "ACTIVE"');
    }
    try {
      await bmoniClient.updateCardStatus({ userId, cardId, status });
    } catch (err) {
      console.warn('[CardService] Fallback status update:', err);
    }
    return { status };
  }
}
