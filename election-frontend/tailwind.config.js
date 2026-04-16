/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx,ts,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: '#FDF6E3',
        surface: '#F5E6C8',
        primary: '#8B6914',
        accent: '#B8860B',
        dark: '#4A3000',
        subtle: '#AA8844',
        border: '#D4A843',
        error: '#C0392B',
        success: '#2D6A1E',
        info: '#1A5276',
        armed: '#C0392B',
        unarmed: '#27AE60',
      },
      fontFamily: {
        sans: ['Tiro Devanagari Hindi', 'Noto Serif Devanagari', 'Georgia', 'serif'],
        mono: ['JetBrains Mono', 'Fira Code', 'monospace'],
        display: ['Playfair Display', 'Georgia', 'serif'],
      },
      boxShadow: {
        card: '0 4px 24px rgba(139, 105, 20, 0.14)',
        modal: '0 10px 40px rgba(139, 105, 20, 0.25)',
      },
    },
  },
  plugins: [],
}
