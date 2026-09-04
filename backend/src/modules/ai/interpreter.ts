import { GoogleGenAI, Type } from '@google/genai';
import { env } from '../../config/env.js';
import { Money, type SupportedCurrency } from '../../core/money.js';

export interface StructuredFinancialIntent {
  intentId: string;
  originalPrompt: string;
  operationType: 'TRANSFER' | 'PAYROLL_RUN' | 'CARD_SPEND_LIMIT' | 'MISSION_CREATE' | 'CURRENCY_SWAP';
  parameters: {
    recipientIdentifier?: string; // email, username, or employee name
    recipientUserId?: string;
    sourceCurrency: SupportedCurrency;
    targetCurrency?: SupportedCurrency;
    amountMinor?: string;
    amountFormatted?: string;
    description?: string;
  };
  explanation: string;
  confidenceScore: number;
  requiresExplicitApproval: true; // Hardcoded invariant: Always requires approval
  provider?: 'gemini' | 'deterministic-fallback';
}

export class FinancialIntentInterpreter {
  /**
   * Interprets natural language prompt into a structured financial intent.
   * If GEMINI_API_KEY is configured, uses Google Gemini (gemini-2.5-flash)
   * with strict JSON Schema output.
   * If not configured or if the LLM call fails, falls back gracefully to deterministic rule extraction.
   * AI NEVER executes money movement; it only produces structured parameters.
   */
  static async interpret(prompt: string): Promise<StructuredFinancialIntent> {
    const trimmed = prompt.trim();
    const intentId = `intent_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;

    if (env.GEMINI_API_KEY && env.GEMINI_API_KEY.trim() !== '') {
      try {
        const ai = new GoogleGenAI({ apiKey: env.GEMINI_API_KEY });
        const response = await ai.models.generateContent({
          model: 'gemini-3.1-flash',
          contents: `Parse this natural language financial request into structured parameters: "${trimmed}"`,
          config: {
            systemInstruction: `You are the FlowPay Financial AI Operator.
Parse user financial requests into structured JSON.
FlowPay supports currencies: USD, NGN, MXN, CAD, EUR.
Never execute or finalize transactions; only extract proposed parameters.
Always produce valid JSON matching the schema.`,
            responseMimeType: 'application/json',
            responseJsonSchema: {
              type: Type.OBJECT,
              properties: {
                operationType: {
                  type: Type.STRING,
                  enum: ['TRANSFER', 'PAYROLL_RUN', 'CARD_SPEND_LIMIT', 'MISSION_CREATE', 'CURRENCY_SWAP'],
                  description: 'Type of financial operation intended',
                },
                recipientIdentifier: {
                  type: Type.STRING,
                  description: 'Recipient name, email, or handle',
                },
                sourceCurrency: {
                  type: Type.STRING,
                  enum: ['USD', 'NGN', 'MXN', 'CAD', 'EUR'],
                  description: 'Source or settlement currency',
                },
                targetCurrency: {
                  type: Type.STRING,
                  enum: ['USD', 'NGN', 'MXN', 'CAD', 'EUR'],
                  description: 'Destination currency for cross-border swap or payouts',
                },
                amount: {
                  type: Type.STRING,
                  description: 'Numeric decimal amount (e.g. "500.00")',
                },
                description: {
                  type: Type.STRING,
                  description: 'Brief description/memo of the transaction',
                },
                explanation: {
                  type: Type.STRING,
                  description: 'User-friendly summary of the proposed action',
                },
                confidenceScore: {
                  type: Type.NUMBER,
                  description: 'Confidence between 0.0 and 1.0',
                },
              },
              required: ['operationType', 'sourceCurrency', 'explanation', 'confidenceScore'],
            },
          },
        });

        if (response.text) {
          const parsed = JSON.parse(response.text);
          const currency: SupportedCurrency = (['USD', 'NGN', 'MXN', 'CAD', 'EUR'].includes(parsed.sourceCurrency)
            ? parsed.sourceCurrency
            : 'USD') as SupportedCurrency;

          let amountMinor = '0';
          let amountFormatted = '0.00';
          if (parsed.amount) {
            try {
              const money = Money.fromMajor(String(parsed.amount).replace(/,/g, ''), currency);
              amountMinor = money.amountMinor.toString();
              amountFormatted = money.toMajorString();
            } catch {
              // Ignore parse error and keep 0
            }
          }

          return {
            intentId,
            originalPrompt: trimmed,
            operationType: parsed.operationType || 'TRANSFER',
            parameters: {
              recipientIdentifier: parsed.recipientIdentifier,
              sourceCurrency: currency,
              targetCurrency: parsed.targetCurrency as SupportedCurrency | undefined,
              amountMinor,
              amountFormatted,
              description: parsed.description || `FlowPay: ${parsed.operationType}`,
            },
            explanation: parsed.explanation || `Proposed ${parsed.operationType} of ${amountFormatted} ${currency}.`,
            confidenceScore: Math.min(1.0, Math.max(0.0, parsed.confidenceScore ?? 0.95)),
            requiresExplicitApproval: true,
            provider: 'gemini',
          };
        }
      } catch (err) {
        console.warn('[Gemini AI] Call failed, falling back to deterministic extraction:', err);
      }
    }

    return this.interpretDeterministic(trimmed, intentId);
  }

  /**
   * Deterministic fallback rule-based extraction (instant, offline, zero API-key requirement)
   */
  static interpretDeterministic(prompt: string, intentId?: string): StructuredFinancialIntent {
    const trimmed = prompt.trim();
    const id = intentId || `intent_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;

    // Rule 1: Multi-country / aggregate payroll command
    if (/payroll|pay (all|team|employees)/i.test(trimmed)) {
      return {
        intentId: id,
        originalPrompt: trimmed,
        operationType: 'PAYROLL_RUN',
        parameters: {
          sourceCurrency: 'USD',
          description: 'Multi-country payroll disbursement',
        },
        explanation: 'Run payroll for all linked employees in their local currencies with aggregate USD settlement.',
        confidenceScore: 0.95,
        requiresExplicitApproval: true,
        provider: 'deterministic-fallback',
      };
    }

    // Rule 2: Transfer / Send money
    // e.g. "Send $250 to Bunch Dillon" or "Pay 50,000 NGN to Samson"
    const amountCurrencyMatch = trimmed.match(/(?:\$|USD\s*|NGN\s*|MXN\s*|CAD\s*|EUR\s*)?([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)\s*(USD|NGN|MXN|CAD|EUR|dollars?|naira|pesos?)?/i);
    const recipientMatch = trimmed.match(/(?:to|for)\s+([A-Za-z0-9._%+-]+(?:@[A-Za-z0-9.-]+\.[A-Za-z]{2,})?|[A-Z][a-z]+\s+[A-Z][a-z]+)/i);

    let currency: SupportedCurrency = 'USD';
    if (/naira|ngn/i.test(trimmed)) currency = 'NGN';
    else if (/pesos|mxn/i.test(trimmed)) currency = 'MXN';
    else if (/cad|canad/i.test(trimmed)) currency = 'CAD';
    else if (/eur|euro/i.test(trimmed)) currency = 'EUR';

    let amountMinor = '0';
    let amountFormatted = '0.00';

    if (amountCurrencyMatch && amountCurrencyMatch[1]) {
      const cleanNum = amountCurrencyMatch[1].replace(/,/g, '');
      const money = Money.fromMajor(cleanNum, currency);
      amountMinor = money.amountMinor.toString();
      amountFormatted = money.toMajorString();
    }

    const recipient = recipientMatch ? recipientMatch[1].trim() : undefined;

    return {
      intentId: id,
      originalPrompt: trimmed,
      operationType: 'TRANSFER',
      parameters: {
        recipientIdentifier: recipient,
        sourceCurrency: currency,
        amountMinor,
        amountFormatted,
        description: `Transfer to ${recipient ?? 'recipient'}`,
      },
      explanation: `Prepared transfer proposal of ${amountFormatted} ${currency} to ${recipient ?? 'unspecified recipient'}. Awaiting your deterministic validation and PIN approval.`,
      confidenceScore: recipient && amountMinor !== '0' ? 0.9 : 0.6,
      requiresExplicitApproval: true,
      provider: 'deterministic-fallback',
    };
  }
}
