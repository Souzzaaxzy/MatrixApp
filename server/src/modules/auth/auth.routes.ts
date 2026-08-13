import type { FastifyInstance, FastifyPluginAsync } from 'fastify';
import type { ZodType } from 'zod';
import { ApiError, toApiError } from '../../utils/errors.js';
import { logger } from '../../config/logger.js';
import { register, login, refresh, logout, getCurrentUser } from './auth.service.js';
import { loginSchema, refreshSchema, registerSchema } from './auth.schema.js';

function parse<T>(schema: ZodType<T>, data: unknown): T {
  const result = schema.safeParse(data);
  if (!result.success) {
    throw ApiError.validation('Dados inválidos.', result.error.issues);
  }
  return result.data;
}

export const authRoutes: FastifyPluginAsync = async (app: FastifyInstance) => {
  app.post('/register', async (request, reply) => {
    try {
      const input = parse(registerSchema, request.body);
      const result = await register(input);
      return reply.status(201).send(result);
    } catch (err) {
      const apiErr = toApiError(err);
      logger.warn({ code: apiErr.code }, 'register failed');
      throw apiErr;
    }
  });

  app.post('/login', async (request, reply) => {
    try {
      const input = parse(loginSchema, request.body);
      const result = await login(input);
      return reply.send(result);
    } catch (err) {
      const apiErr = toApiError(err);
      logger.warn({ code: apiErr.code }, 'login failed');
      throw apiErr;
    }
  });

  app.post('/refresh', async (request, reply) => {
    const input = parse(refreshSchema, request.body);
    const result = await refresh(input.refreshToken);
    return reply.send(result);
  });

  app.get('/me', { onRequest: [app.authenticate] }, async (request, reply) => {
    const user = await getCurrentUser(request.user!.id);
    return reply.send({ user });
  });

  app.post('/logout', async (request, reply) => {
    const body = (request.body ?? {}) as { refreshToken?: string };
    if (body.refreshToken) {
      await logout(body.refreshToken);
    }
    return reply.status(204).send();
  });
};
