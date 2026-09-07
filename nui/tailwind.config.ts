import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./src/pages/**/*.{ts,tsx}', './src/components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        paper: '#e6d9b8',
        'paper-dark': '#d8c69a',
        ink: '#1f2a33',
        'ink-light': '#3a4a56',
        rail: '#12222d',
        brass: '#b8862f',
        'brass-light': '#d9a94a',
        rust: '#7a2320',
        'rust-light': '#9c2f2b',
        // Selected/active state (chosen tabs, toggles) and focus highlight on inputs.
        select: '#28292A',
      },
      fontFamily: {
        display: ['var(--font-display)', 'serif'],
        body: ['var(--font-body)', 'serif'],
      },
    },
  },
  plugins: [],
};

export default config;
