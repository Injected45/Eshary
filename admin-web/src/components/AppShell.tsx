'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useState, type ReactNode } from 'react';
import { logoutAction } from '@/app/(app)/actions';

export type NavItem = { href: string; label: string };

export function AppShell({
  nav,
  name,
  roleLabel,
  children,
}: {
  nav: NavItem[];
  name: string;
  roleLabel: string;
  children: ReactNode;
}) {
  const path = usePathname();
  const [open, setOpen] = useState(false);
  const active = (href: string) =>
    href === '/' ? path === '/' : path === href || path.startsWith(`${href}/`);

  return (
    <div className="shell">
      <div className="topbar">
        <button className="btn" aria-label="القائمة" onClick={() => setOpen((v) => !v)}>
          ☰
        </button>
        <strong>إشاري</strong>
      </div>
      <aside className={`side${open ? ' open' : ''}`}>
        <div className="brand">
          <img src="/icon-192.png" width={36} height={36} alt="" />
          <span>إشاري</span>
        </div>
        <nav className="nav" onClick={() => setOpen(false)}>
          {nav.map((n) => (
            <Link key={n.href} href={n.href} className={active(n.href) ? 'active' : ''}>
              {n.label}
            </Link>
          ))}
        </nav>
        <div className="who">
          <div>{name}</div>
          <div className="muted">{roleLabel}</div>
          <form action={logoutAction}>
            <button className="btn link" type="submit">تسجيل الخروج</button>
          </form>
        </div>
      </aside>
      <main className="main">{children}</main>
    </div>
  );
}
