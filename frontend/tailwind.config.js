/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        bg:      '#FDF6E3',
        surface: '#F5E6C8',
        primary: '#8B6914',
        accent:  '#B8860B',
        dark:    '#4A3000',
        subtle:  '#AA8844',
        border:  '#D4A843',
        danger:  '#C0392B',
      },
      fontFamily: {
        sans: ['Inter', 'Roboto', 'sans-serif'],
      }
    },
  },
  plugins: [],
}
