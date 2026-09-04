export class FlowPayError extends Error {
  constructor(
    message: string,
    public readonly statusCode: number = 500,
    public readonly code: string = 'INTERNAL_ERROR',
    public readonly details?: unknown
  ) {
    super(message);
    this.name = 'FlowPayError';
  }
}

export class ValidationError extends FlowPayError {
  constructor(message: string, details?: unknown) {
    super(message, 400, 'VALIDATION_ERROR', details);
    this.name = 'ValidationError';
  }
}

export class BmoniApiError extends FlowPayError {
  constructor(
    message: string,
    statusCode: number,
    public readonly bmoniError?: string,
    details?: unknown
  ) {
    super(message, statusCode, 'BMONI_API_ERROR', details);
    this.name = 'BmoniApiError';
  }
}

export class FinancialSafetyError extends FlowPayError {
  constructor(message: string, details?: unknown) {
    super(message, 422, 'FINANCIAL_SAFETY_VIOLATION', details);
    this.name = 'FinancialSafetyError';
  }
}

export class UnauthorizedError extends FlowPayError {
  constructor(message: string = 'Unauthorized') {
    super(message, 401, 'UNAUTHORIZED');
    this.name = 'UnauthorizedError';
  }
}

export class NotFoundError extends FlowPayError {
  constructor(message: string = 'Resource not found') {
    super(message, 404, 'NOT_FOUND');
    this.name = 'NotFoundError';
  }
}

export class CardEnrollmentRequiredError extends FlowPayError {
  constructor(message: string = 'Card owner is not enrolled for cards yet. 11-digit NIN is required.') {
    super(message, 400, 'E101', { isEnrollmentRequired: true });
    this.name = 'CardEnrollmentRequiredError';
  }
}

export class InsufficientFundsError extends FlowPayError {
  constructor(message: string = 'Insufficient funds across available smart wallets for this operation.') {
    super(message, 400, 'INSUFFICIENT_FUNDS');
    this.name = 'InsufficientFundsError';
  }
}

export class InvalidRequestError extends FlowPayError {
  constructor(message: string, details?: unknown) {
    super(message, 400, 'INVALID_REQUEST', details);
    this.name = 'InvalidRequestError';
  }
}

export class KycOnboardingError extends FlowPayError {
  constructor(message: string, details?: unknown) {
    super(message, 400, 'KYC_ONBOARDING_FAILED', details);
    this.name = 'KycOnboardingError';
  }
}

export class SignatureFailureError extends FlowPayError {
  constructor(message: string = 'B-Key on-device hardware PIN signature verification failed.') {
    super(message, 400, 'SIGNATURE_FAILURE');
    this.name = 'SignatureFailureError';
  }
}

export class ProposalExpiredError extends FlowPayError {
  constructor(message: string = 'The financial proposal has expired. Please review updated rates and generate a new proposal.') {
    super(message, 400, 'PROPOSAL_EXPIRED');
    this.name = 'ProposalExpiredError';
  }
}

export class UnsupportedCurrencyError extends FlowPayError {
  constructor(currency: string) {
    super(`Currency ${currency} is not supported on available BMONI rails. Supported: USD, NGN, MXN, CAD, EUR.`, 400, 'UNSUPPORTED_CURRENCY');
    this.name = 'UnsupportedCurrencyError';
  }
}

export class BmoniTimeoutError extends FlowPayError {
  constructor(message: string = 'BMONI rail communication timed out. Please retry or check activity status.') {
    super(message, 504, 'BMONI_TIMEOUT');
    this.name = 'BmoniTimeoutError';
  }
}

export class BmoniUnavailableError extends FlowPayError {
  constructor(message: string = 'BMONI infrastructure rail is temporarily unavailable. Demo fallback active.') {
    super(message, 503, 'BMONI_UNAVAILABLE');
    this.name = 'BmoniUnavailableError';
  }
}

/**
 * Sanitizes BMONI errors to safe FlowPay errors, never exposing raw internal stack or partner credentials
 */
export function sanitizeBmoniError(err: unknown): FlowPayError {
  if (err instanceof FlowPayError) {
    if (err instanceof BmoniApiError) {
      const msg = (err.message || '').toLowerCase();
      if (err.statusCode === 504 || msg.includes('timed out') || msg.includes('timeout')) {
        return new BmoniTimeoutError();
      }
      if (err.statusCode === 502 || err.statusCode === 503 || msg.includes('unavailable') || msg.includes('econnrefused')) {
        return new BmoniUnavailableError();
      }
      if (msg.includes('insufficient') || msg.includes('balance')) {
        return new InsufficientFundsError(err.message);
      }
      if (msg.includes('point is not on curve') || msg.includes('parity') || msg.includes('signature')) {
        return new SignatureFailureError('Cryptographic signature verification failed on BMONI rails.');
      }
      if (msg.includes('expired') || msg.includes('deadline')) {
        return new ProposalExpiredError();
      }
      if (msg.includes('e101') || msg.includes('not enrolled')) {
        return new CardEnrollmentRequiredError();
      }
      if (err.statusCode === 400) {
        return new InvalidRequestError(err.message);
      }
      // Mask any unexpected internal 500
      if (err.statusCode >= 500) {
        return new BmoniUnavailableError('BMONI processing error. Safe fallback maintained.');
      }
    }
    return err;
  }
  return new FlowPayError('An unexpected internal error occurred.');
}
