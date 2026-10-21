import { headers } from 'next/headers';

/** The caller's address as the hosting platform reports it. */
export async function clientIp(): Promise<string> {
  const h = await headers();
  const fwd = h.get('x-forwarded-for') ?? '';
  return (fwd.split(',')[0] || h.get('x-real-ip') || 'unknown').trim().slice(0, 64);
}
