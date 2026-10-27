import Fastify from 'fastify';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import cors from '@fastify/cors';
import type { Deps } from './deps.ts';
import { one } from './db.ts';
import { AppError, forbidden, notFound, unauthorized } from './errors.ts';
import { safeEqual } from './crypto.ts';
import * as auth from './auth.ts';
import * as ledger from './ledger.ts';
import * as voices from './voices.ts';
import * as jobs from './jobs.ts';
import * as songs from './songs.ts';
import * as account from './account.ts';
import { allConsentStatements } from './consent.ts';
import { metrics } from './metrics.ts';
import { audit } from './audit.ts';
import { RateLimiter } from './ratelimit.ts';

declare module 'fastify' {
  interface FastifyRequest {
    auth: auth.AuthedUser | null;
  }
}

const str = (max: number, min = 1) => ({ type: 'string', minLength: min, maxLength: max }) as const;
const strMap = { type: 'object', additionalProperties: { type: 'string', maxLength: 100 }, maxProperties: 20 } as const;

export function buildApp(deps: Deps): FastifyInstance {
  // Strict validation: unknown fields are errors (not silently dropped) and values are never coerced.
  const app = Fastify({
    bodyLimit: 256 * 1024, trustProxy: false, logger: false,
    ajv: { customOptions: { removeAdditional: false, coerceTypes: false, useDefaults: false, allErrors: false } },
  });
  const { db, clock, config } = deps;

  const loginLimit = new RateLimiter(clock, 10, 60_000);
  const registerLimit = new RateLimiter(clock, 5, 60_000);
  const jobLimit = new RateLimiter(clock, 20, 60_000);
  const uploadLimit = new RateLimiter(clock, 10, 60_000);
  // Keyed by account: a stolen session token must not be able to guess the password here.
  const deleteLimit = new RateLimiter(clock, 5, 60_000);

  void app.register(cors, {
    origin: config.corsOrigins.length ? config.corsOrigins : false,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type', 'Idempotency-Key'],
    maxAge: 600,
  });

  app.decorateRequest('auth', null);

  app.addContentTypeParser(/^audio\/.+|^application\/octet-stream$/, { parseAs: 'buffer', bodyLimit: config.maxVoiceBytes },
    (_req, body, done) => done(null, body));

  app.addHook('onSend', async (_req, reply) => {
    reply.header('X-Content-Type-Options', 'nosniff');
    reply.header('Referrer-Policy', 'no-referrer');
  });

  app.setErrorHandler((err: unknown, req, reply) => {
    if (err instanceof AppError) {
      return reply.status(err.status).send({ error: { code: err.code, message: err.message, ...(err.details ? { details: err.details } : {}) } });
    }
    const e = err as { statusCode?: number; code?: string; validation?: unknown; message?: string };
    if (e.validation) {
      return reply.status(400).send({ error: { code: 'invalid_request', message: 'The request is not valid.', details: { problem: e.message } } });
    }
    if (e.statusCode === 413) return reply.status(413).send({ error: { code: 'payload_too_large', message: 'That upload is too large.' } });
    if (e.statusCode && e.statusCode >= 400 && e.statusCode < 500) {
      return reply.status(e.statusCode).send({ error: { code: e.code ?? 'bad_request', message: 'The request could not be processed.' } });
    }
    deps.log.error({ err: String(err), url: req.url }, 'unhandled error');
    return reply.status(500).send({ error: { code: 'internal_error', message: 'Something went wrong on our side.' } });
  });

  app.setNotFoundHandler((_req, reply) => reply.status(404).send({ error: { code: 'not_found', message: 'Not found.' } }));

  const bearer = (req: FastifyRequest): string | null => {
    const h = req.headers.authorization;
    return h && h.startsWith('Bearer ') ? h.slice(7).trim() || null : null;
  };
  const requireAuth = async (req: FastifyRequest) => {
    req.auth = auth.authenticate(db, clock, bearer(req));
  };
  const uid = (req: FastifyRequest): string => {
    if (!req.auth) throw unauthorized();
    return req.auth.userId;
  };
  const requireAdmin = async (req: FastifyRequest) => {
    const token = bearer(req);
    if (!config.adminToken || !token || !safeEqual(token, config.adminToken)) throw forbidden();
  };

  // ---------------------------------------------------------------- public
  app.get('/healthz', async () => ({
    ok: true,
    provider: { name: deps.provider.name, configured: deps.provider.configured, available: !deps.health.isBlocked(clock) },
  }));

  app.get('/v1/consent-statements', async () => allConsentStatements());

  const credentialsBody = {
    type: 'object', required: ['email', 'password'], additionalProperties: false,
    properties: { email: str(254), password: str(200) },
  } as const;

  app.post('/v1/auth/register', { schema: { body: credentialsBody } }, async (req, reply) => {
    if (!registerLimit.allow(req.ip)) throw new AppError(429, 'rate_limited', 'Too many attempts. Wait a minute.');
    const b = req.body as { email: string; password: string };
    const r = await auth.register(db, clock, config.sessionTtlMs, b.email, b.password);
    return reply.status(201).send({ userId: r.userId, email: r.email, token: r.token, expiresAt: r.expiresAt });
  });

  app.post('/v1/auth/login', { schema: { body: credentialsBody } }, async (req) => {
    if (!loginLimit.allow(req.ip)) throw new AppError(429, 'rate_limited', 'Too many attempts. Wait a minute.');
    const b = req.body as { email: string; password: string };
    const r = await auth.login(db, clock, config.sessionTtlMs, b.email, b.password);
    return { userId: r.userId, email: r.email, token: r.token, expiresAt: r.expiresAt };
  });

  // --------------------------------------------------------------- signed media
  app.get('/media/songs/:id', async (req, reply) => {
    const { id } = req.params as { id: string };
    const q = req.query as { exp?: string; sig?: string };
    const { data, mime } = await songs.readSongAudio(deps, id, Number(q.exp), String(q.sig ?? ''));
    reply.header('Content-Type', mime).header('Accept-Ranges', 'bytes').header('Cache-Control', 'private, no-store');
    const range = req.headers.range;
    if (!range) return reply.header('Content-Length', data.length).send(data);
    const m = /^bytes=(\d*)-(\d*)$/.exec(range);
    if (!m || (m[1] === '' && m[2] === '')) {
      return reply.status(416).header('Content-Range', `bytes */${data.length}`).send();
    }
    let start: number;
    let end: number;
    if (m[1] === '') { // suffix range: last N bytes
      start = Math.max(0, data.length - Number(m[2]));
      end = data.length - 1;
    } else {
      start = Number(m[1]);
      end = m[2] === '' ? data.length - 1 : Math.min(Number(m[2]), data.length - 1);
    }
    if (start >= data.length || start > end) {
      return reply.status(416).header('Content-Range', `bytes */${data.length}`).send();
    }
    const part = data.subarray(start, end + 1);
    return reply.status(206).header('Content-Range', `bytes ${start}-${end}/${data.length}`)
      .header('Content-Length', part.length).send(part);
  });

  // -------------------------------------------------------- authenticated API
  app.register(async (api) => {
    // onRequest: authenticate before the body is read or validated, so anonymous callers learn nothing.
    api.addHook('onRequest', requireAuth);

    api.post('/auth/logout', async (req, reply) => {
      auth.logout(db, clock, req.auth!.sessionId);
      return reply.status(204).send();
    });

    api.get('/me', async (req) => {
      const row = one(db, 'SELECT id, email, created_at FROM users WHERE id = ?', uid(req))!;
      return { userId: String(row['id']), email: String(row['email']), createdAt: String(row['created_at']), credits: ledger.balance(db, uid(req)) };
    });

    api.delete('/me', {
      schema: { body: { type: 'object', required: ['password'], additionalProperties: false, properties: { password: str(200) } } },
    }, async (req) => {
      if (!deleteLimit.allow(uid(req))) throw new AppError(429, 'rate_limited', 'Too many attempts. Wait a minute.');
      return account.deleteAccount(deps, uid(req), (req.body as { password: string }).password);
    });

    api.get('/credits', async (req) => ledger.balance(db, uid(req)));
    api.get('/credits/transactions', async (req) => ({ transactions: ledger.transactions(db, uid(req)) }));

    // --- generation
    api.get('/generation/capabilities', async () => {
      const c = deps.provider.capabilities();
      return {
        engineName: c.engineName, songTypes: c.songTypes, languages: c.languages,
        documentedLanguages: c.documentedLanguages, voiceConditioning: c.voiceConditioning,
        advancedOptionIds: c.advancedOptionIds, voiceSampleSeconds: c.voiceSampleSeconds,
        available: deps.provider.configured && !deps.health.isBlocked(clock),
      };
    });
    api.get('/generation/quote', async () => jobs.quote(deps));

    const jobBody = {
      type: 'object', additionalProperties: false,
      required: ['idempotencyKey', 'title', 'lyrics', 'language', 'songType'],
      properties: {
        idempotencyKey: str(128, 8), title: str(200), lyrics: str(20000), language: str(40), songType: str(40),
        voiceId: { type: ['string', 'null'], maxLength: 64 }, style: strMap, advanced: strMap,
      },
    } as const;
    api.post('/generation/jobs', { schema: { body: jobBody } }, async (req, reply) => {
      if (!jobLimit.allow(uid(req))) throw new AppError(429, 'rate_limited', 'Too many songs requested. Wait a minute.');
      const b = req.body as Omit<jobs.CreateJobInput, 'voiceId' | 'style' | 'advanced'> & {
        voiceId?: string | null; style?: Record<string, string>; advanced?: Record<string, string>;
      };
      const r = jobs.createJob(deps, uid(req), { ...b, voiceId: b.voiceId ?? null, style: b.style ?? {}, advanced: b.advanced ?? {} });
      return reply.status(r.deduplicated ? 200 : 202).send({ job: r.job, deduplicated: r.deduplicated });
    });
    api.get('/generation/jobs', async (req) => ({ jobs: jobs.listJobs(deps, uid(req)) }));
    api.get('/generation/jobs/:id', async (req) => ({ job: jobs.getJob(deps, uid(req), (req.params as { id: string }).id) }));
    api.post('/generation/jobs/:id/cancel', async (req) => ({ job: jobs.cancelJob(deps, uid(req), (req.params as { id: string }).id) }));

    // --- voices
    api.get('/voices', async (req) => ({ voices: voices.listVoices(deps, uid(req)) }));
    api.post('/voices', {
      schema: {
        body: {
          type: 'object', additionalProperties: false, required: ['displayName', 'ownership', 'consent'],
          properties: {
            displayName: str(100), ownership: { enum: ['own', 'authorized'] }, authorizedBy: { type: ['string', 'null'], maxLength: 100 },
            consent: { type: 'object', additionalProperties: false, required: ['accepted', 'version'],
              properties: { accepted: { type: 'boolean' }, version: str(20) } },
          },
        },
      },
    }, async (req, reply) => {
      const b = req.body as { displayName: string; ownership: 'own' | 'authorized'; authorizedBy?: string | null; consent: { accepted: boolean; version: string } };
      const v = voices.createVoice(deps, uid(req), { ...b, authorizedBy: b.authorizedBy ?? null },
        { ip: req.ip, userAgent: (req.headers['user-agent'] ?? null) as string | null });
      return reply.status(201).send({ voice: v });
    });
    api.put('/voices/:id/audio', { bodyLimit: config.maxVoiceBytes }, async (req) => {
      if (!uploadLimit.allow(uid(req))) throw new AppError(429, 'rate_limited', 'Too many uploads. Wait a minute.');
      if (!Buffer.isBuffer(req.body)) throw new AppError(415, 'audio_required', 'Send the recording as the request body with an audio content type.');
      return { voice: await voices.uploadVoiceAudio(deps, uid(req), (req.params as { id: string }).id, req.body) };
    });
    api.post('/voices/:id/retry', async (req) => ({ voice: voices.retryEnrollment(deps, uid(req), (req.params as { id: string }).id) }));
    api.post('/voices/:id/revoke', async (req) => ({ voice: voices.revokeVoice(deps, uid(req), (req.params as { id: string }).id) }));
    api.delete('/voices/:id', async (req) => {
      const q = req.query as { deleteSongs?: string };
      return voices.deleteVoice(deps, uid(req), (req.params as { id: string }).id, { deleteSongs: q.deleteSongs === 'true' });
    });

    // --- songs
    api.get('/songs', async (req) => ({ songs: songs.listSongs(deps, uid(req)) }));
    api.get('/songs/:id', async (req) => ({ song: songs.getSong(deps, uid(req), (req.params as { id: string }).id) }));
    api.patch('/songs/:id', { schema: { body: { type: 'object', additionalProperties: false, required: ['title'], properties: { title: str(200) } } } },
      async (req) => ({ song: songs.renameSong(deps, uid(req), (req.params as { id: string }).id, (req.body as { title: string }).title) }));
    api.delete('/songs/:id', async (req, reply) => {
      await songs.deleteSong(deps, uid(req), (req.params as { id: string }).id);
      return reply.status(204).send();
    });
    api.post('/songs/:id/audio-url', async (req) => songs.signAudioUrl(deps, uid(req), (req.params as { id: string }).id));
  }, { prefix: '/v1' });

  // ------------------------------------------------------------- operator API
  app.register(async (admin) => {
    admin.addHook('onRequest', requireAdmin);
    admin.post('/credits/grant', {
      schema: { body: { type: 'object', additionalProperties: false, required: ['amount', 'note'],
        properties: { email: str(254), userId: str(64), amount: { type: 'integer', minimum: 1, maximum: 100000 }, note: str(200) } } },
    }, async (req) => {
      const b = req.body as { email?: string; userId?: string; amount: number; note: string };
      const user = b.userId
        ? one(db, 'SELECT id FROM users WHERE id = ?', b.userId)
        : one(db, 'SELECT id FROM users WHERE email = ?', (b.email ?? '').trim().toLowerCase());
      if (!user) throw notFound('User');
      const userId = String(user['id']);
      ledger.grant(db, clock, userId, b.amount, b.note);
      audit(db, clock, { kind: 'credits.granted', subjectType: 'user', subjectId: userId, detail: { amount: b.amount } });
      return ledger.balance(db, userId);
    });
    admin.get('/metrics', async (req) => {
      const since = (req.query as { since?: string }).since ?? '1970-01-01T00:00:00.000Z';
      return metrics(deps, since);
    });
    admin.post('/provider/reset-health', async () => {
      deps.health.clear();
      return { ok: true };
    });
  }, { prefix: '/v1/admin' });

  return app;
}

export type { FastifyReply };
