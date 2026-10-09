import type { MetadataRoute } from "next";
export default function manifest(): MetadataRoute.Manifest {
  return { name: "SANTRI DEPROK", short_name: "SANTRI DEPROK", description: "Sistem Keuangan Haul KH. Ahmad Baehaqi Sholihin", start_url: "/", display: "standalone", background_color: "#f7f8f5", theme_color: "#145536", icons: [] };
}