import type { Metadata, Viewport } from 'next';
import './globals.css';
import { RegisterSw } from '@/components/RegisterSw';

export const metadata: Metadata = {
  title: 'إشاري | ESHARI Admin',
  description: 'منصة إدارة وتحكم تطبيق إشاري',
  manifest: '/manifest.webmanifest',
  icons: { icon: '/favicon.png', apple: '/icon-192.png' },
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: '#0b1220',
  width: 'device-width',
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ar" dir="rtl">
      <body>
        {children}
        <RegisterSw />
      </body>
    </html>
  );
}
