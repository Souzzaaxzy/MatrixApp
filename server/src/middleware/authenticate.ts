import type { FastifyReply, FastifyRequest } from 'fastify';
import { ApiError } from '../utils/errors.js';
import { verifyAccessToken } from '../utils/auth.js';

declare module 'fastify' {
  interface FastifyInstance {
    authenticate: (request: FastifyRequest, _reply: FastifyReply) => Promise<void>;
    optionalAuth: (request: FastifyRequest, _reply: FastifyReply) => Promise<void>;
  }
}

export async function authenticate(request: FastifyRequest, _reply: FastifyReply): Promise<void> {
  const header = request.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    throw ApiError.unauthorized();
  }
  const token = header.slice('Bearer '.length).trim();
  try {
    const payload = verifyAccessToken(token);
    request.user = { id: payload.sub, username: payload.username };
  } catch {
    throw ApiError.unauthorized();
  }
}

// Populates request.user when a valid bearer token is present, but does
// NOT reject the request when absent or invalid. Used by public routes
// (feed, profile) that personalize ("liked" state) for logged-in users.
export async function optionalAuth(request: FastifyRequest, _reply: FastifyReply): Promise<void> {
  const header = request.headers.authorization;
  if (!header?.startsWith('Bearer ')) return;
  const token = header.slice('Bearer '.length).trim();
  try {
    const payload = verifyAccessToken(token);
    request.user = { id: payload.sub, username: payload.username };
  } catch {
    // Invalid token on a public route — ignore and treat as anonymous.
  }
}
