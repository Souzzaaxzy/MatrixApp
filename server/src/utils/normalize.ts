// Input normalization helpers. Centralized so every endpoint treats
// email/username consistently regardless of where they enter the system.

export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

// Usernames: lowercase, trim. Allow letters, numbers, underscores, dots, hyphens.
export function normalizeUsername(username: string): string {
  return username.trim().toLowerCase();
}

export function isValidUsername(username: string): boolean {
  const normalized = normalizeUsername(username);
  return /^[a-z0-9._-]{3,20}$/.test(normalized) && /^[a-z0-9]/.test(normalized);
}

export function isValidEmail(email: string): boolean {
  return /^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$/i.test(normalizeEmail(email));
}
