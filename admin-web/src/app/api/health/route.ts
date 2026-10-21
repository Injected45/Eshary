import { NextResponse } from 'next/server';

// Public, no data: lets the hosting platform and an uptime monitor see that the
// site answers. The database state is on the signed-in "حالة النظام" page.
export const dynamic = 'force-dynamic';

export function GET() {
  return NextResponse.json({ ok: true, app: 'eshary-admin' });
}
