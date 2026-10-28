import { AppShell, type NavItem } from '@/components/AppShell';
import { requireStaff } from '@/lib/auth';
import { roleLabel } from '@/lib/format';

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const me = await requireStaff();
  const writer = me.role === 'super_admin' || me.role === 'admin';
  const nav: NavItem[] = [
    { href: '/', label: 'لوحة التحكم' },
    { href: '/users', label: 'المستخدمون' },
    ...(writer
      ? [
          { href: '/requests', label: 'طلبات التفعيل' },
          { href: '/notifications', label: 'مركز الإشعارات' },
          { href: '/audit', label: 'سجل العمليات' },
        ]
      : []),
    { href: '/updates', label: 'تحديثات التطبيق' },
    { href: '/system', label: 'حالة النظام' },
    ...(me.role === 'super_admin' ? [{ href: '/staff', label: 'الحسابات الإدارية' }] : []),
    ...(writer ? [{ href: '/settings', label: 'الإعدادات' }] : []),
  ];
  return (
    <AppShell nav={nav} name={me.name} roleLabel={roleLabel[me.role]}>
      {children}
    </AppShell>
  );
}
