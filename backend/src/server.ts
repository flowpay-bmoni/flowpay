import cors from 'cors';
import express, { type NextFunction, type Request, type Response } from 'express';
import { env } from './config/env.js';
import { FlowPayError, sanitizeBmoniError } from './core/errors.js';
import { initDatabase } from './db/index.js';
import { activityRouter } from './routes/activity.routes.js';
import { aiRouter } from './routes/ai.routes.js';
import { authRouter } from './routes/auth.routes.js';
import { cardsRouter } from './routes/cards.routes.js';
import { employeesRouter } from './routes/employees.routes.js';
import { missionsRouter } from './routes/missions.routes.js';
import { payrollRouter } from './routes/payroll.routes.js';
import { transfersRouter } from './routes/transfers.routes.js';
import { walletsRouter } from './routes/wallets.routes.js';
import { webhookRouter } from './routes/webhook.routes.js';
import { webhookConfigRouter } from './routes/webhook-config.routes.js';

const app = express();

// 1. CORS
app.use(cors());

// 2. Webhook route with raw body buffer parsing
// MUST mount before global express.json()
app.use('/webhooks', webhookRouter);

// 3. Global JSON parser for standard API routes
app.use(express.json());

// 4. Health check
app.get('/api/health', (req: Request, res: Response) => {
  res.json({
    status: 'ok',
    service: 'flowpay-backend',
    version: '1.0.0',
    bmoniOrigin: env.BMONI_BASE_URL,
    timestamp: new Date().toISOString(),
  });
});

// 5. Register API routes
app.use('/api/auth', authRouter);
app.use('/api/wallets', walletsRouter);
app.use('/api/transfers', transfersRouter);
app.use('/api/cards', cardsRouter);
app.use('/api/employees', employeesRouter);
app.use('/api/payroll', payrollRouter);
app.use('/api/missions', missionsRouter);
app.use('/api/ai', aiRouter);
app.use('/api/activity', activityRouter);
app.use('/api/webhooks', webhookConfigRouter);

// 6. Global Error Handler
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  const safeErr = sanitizeBmoniError(err);
  if (safeErr instanceof FlowPayError) {
    return res.status(safeErr.statusCode).json({
      success: false,
      statusCode: safeErr.statusCode,
      code: safeErr.code,
      message: safeErr.message,
      details: safeErr.details,
    });
  }

  console.error('[Unhandled Error]', err);
  return res.status(500).json({
    success: false,
    statusCode: 500,
    code: 'INTERNAL_SERVER_ERROR',
    message: 'An unexpected internal error occurred.',
  });
});

// Initialize database and start server
initDatabase();

if (process.env.NODE_ENV !== 'test') {
  app.listen(env.PORT, () => {
    console.log(`=============================================`);
    console.log(` FlowPay Backend Running on http://localhost:${env.PORT}`);
    console.log(` BMONI Infrastructure: ${env.BMONI_BASE_URL}`);
    console.log(` Webhook URL: http://localhost:${env.PORT}/webhooks/bmoni`);
    console.log(`=============================================`);
  });
}

export default app;
