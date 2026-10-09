import type { Metadata, Viewport } from "next";
import "./globals.css";
export const metadata: Metadata = {
  title: "SANTRI DEPROK — Keuangan Haul",
  description: "Sistem pencatatan tabungan sapi dan kas Haul KH. Ahmad Baehaqi Sholihin.",
  applicationName: "SANTRI DEPROK",
  manifest: "/manifest.webmanifest"
};
export const viewport: Viewport = { themeColor: "#145536", width: "device-width", initialScale: 1, maximumScale: 1 };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="id"><body>{children}</body></html>;
}