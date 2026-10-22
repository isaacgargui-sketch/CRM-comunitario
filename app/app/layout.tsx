import './globals.css';
import type { Metadata } from 'next';

export const metadata: Metadata = { title: 'CRM Comunitario Tucumán', robots: { index: false, follow: false } };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es-AR">
      <body>{children}</body>
    </html>
  );
}
