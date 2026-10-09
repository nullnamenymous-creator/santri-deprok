import type { Config } from "tailwindcss";
const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        forest: { 50: "#eff8f2", 100: "#d9efe0", 500: "#218653", 600: "#176b40", 700: "#145536", 900: "#103b2b" },
        sand: { 50: "#fbf8f0", 100: "#f4eddc", 200: "#e8dcc0" }
      },
      boxShadow: { soft: "0 10px 35px rgba(18, 59, 43, .07)" }
    }
  },
  plugins: []
};
export default config;