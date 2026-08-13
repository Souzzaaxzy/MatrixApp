import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildTestServer, closeTestServer, login, createUser, createAndLoginUser } from './helpers.js';
import type { FastifyInstance } from 'fastify';

let server: FastifyInstance;

beforeAll(async () => {
  server = await buildTestServer();
});
afterAll(async () => {
  await closeTestServer();
});

describe('Auth — POST /auth/register', () => {
  it('registers a new user and returns tokens + user', async () => {
    const res = await server.inject({
      method: 'POST',
      url: '/auth/register',
      payload: {
        name: 'Novo Usuário',
        username: 'novouser',
        email: 'novouser@matrix.app',
        password: 'Senha1234',
      },
    });
    expect(res.statusCode).toBe(201);
    const body = JSON.parse(res.payload);
    expect(body.accessToken).toBeTypeOf('string');
    expect(body.refreshToken).toBeTypeOf('string');
    expect(body.user.username).toBe('novouser');
    expect(body.user).not.toHaveProperty('passwordHash');
  });

  it('rejects duplicate username/email with 409', async () => {
    await createUser({ username: 'dupuser', email: 'dup@matrix.app' });
    const res = await server.inject({
      method: 'POST',
      url: '/auth/register',
      payload: {
        name: 'Dup',
        username: 'dupuser',
        email: 'dup@matrix.app',
        password: 'Senha1234',
      },
    });
    expect(res.statusCode).toBe(409);
  });

  it('validates weak password', async () => {
    const res = await server.inject({
      method: 'POST',
      url: '/auth/register',
      payload: {
        name: 'Weak',
        username: 'weakuser',
        email: 'weak@matrix.app',
        password: 'short',
      },
    });
    expect(res.statusCode).toBe(400);
  });
});

describe('Auth — POST /auth/login', () => {
  it('logs in with username', async () => {
    await createUser({ username: 'loginuser', password: 'Password123' });
    const auth = await login(server, 'loginuser', 'Password123');
    expect(auth.accessToken).toBeTypeOf('string');
    expect(auth.user.username).toBe('loginuser');
  });

  it('logs in with email', async () => {
    await createUser({ username: 'emailuser', email: 'email@matrix.app', password: 'Password123' });
    const auth = await login(server, 'email@matrix.app', 'Password123');
    expect(auth.user.username).toBe('emailuser');
  });

  it('rejects wrong password with 401', async () => {
    await createUser({ username: 'wrongpass', password: 'Password123' });
    const res = await server.inject({
      method: 'POST',
      url: '/auth/login',
      payload: { identifier: 'wrongpass', password: 'WrongPass1' },
    });
    expect(res.statusCode).toBe(401);
  });

  it('rejects unknown user with 401 (generic)', async () => {
    const res = await server.inject({
      method: 'POST',
      url: '/auth/login',
      payload: { identifier: 'ghost', password: 'Password123' },
    });
    expect(res.statusCode).toBe(401);
    const body = JSON.parse(res.payload);
    expect(body.error.message).toBe('Credenciais inválidas.');
  });
});

describe('Auth — GET /auth/me', () => {
  it('returns current user when authenticated', async () => {
    const u = await createAndLoginUser(server, { username: 'meuser' });
    const res = await server.inject({
      method: 'GET',
      url: '/auth/me',
      headers: { authorization: `Bearer ${u.accessToken}` },
    });
    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.payload).user.username).toBe('meuser');
  });

  it('rejects unauthenticated access with 401', async () => {
    const res = await server.inject({ method: 'GET', url: '/auth/me' });
    expect(res.statusCode).toBe(401);
  });

  it('rejects malformed token with 401', async () => {
    const res = await server.inject({
      method: 'GET',
      url: '/auth/me',
      headers: { authorization: 'Bearer not-a-jwt' },
    });
    expect(res.statusCode).toBe(401);
  });
});
