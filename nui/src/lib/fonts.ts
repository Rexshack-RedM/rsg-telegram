import { Playfair_Display, Special_Elite } from 'next/font/google';

// Self-hosted at build time by next/font, so the NUI browser never needs to
// reach Google Fonts at runtime.
export const displayFont = Playfair_Display({
  subsets: ['latin'],
  weight: ['700', '900'],
  variable: '--font-display',
});

export const bodyFont = Special_Elite({
  subsets: ['latin'],
  weight: '400',
  variable: '--font-body',
});
