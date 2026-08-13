import { z } from 'zod';
import { isValidEmail, isValidUsername } from '../../utils/normalize.js';

export const registerSchema = z.object({
  name: z.string().trim().min(2, 'Nome muito curto').max(80, 'Nome muito longo'),
  email: z.string().refine(isValidEmail, 'E-mail inválido'),
  username: z.string().refine(isValidUsername, 'Usuário inválido'),
  password: z
    .string()
    .min(8, 'A senha deve ter no mínimo 8 caracteres')
    .max(128, 'Senha muito longa')
    .regex(/[A-Za-z]/, 'A senha deve conter letras')
    .regex(/[0-9]/, 'A senha deve conter números'),
});

export const loginSchema = z.object({
  // Accept either a username or an email — the service resolves which.
  identifier: z.string().trim().min(1, 'Informe usuário ou e-mail'),
  password: z.string().min(1, 'Senha obrigatória'),
});

export const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

export type RegisterInput = z.infer<typeof registerSchema>;
export type LoginInput = z.infer<typeof loginSchema>;
export type RefreshInput = z.infer<typeof refreshSchema>;
