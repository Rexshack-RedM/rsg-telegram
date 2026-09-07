import type { AppProps } from 'next/app';
import '@/styles/globals.css';
import { displayFont, bodyFont } from '@/lib/fonts';

export default function App({ Component, pageProps }: AppProps) {
  return (
    <div className={`${displayFont.variable} ${bodyFont.variable} contents`}>
      <Component {...pageProps} />
    </div>
  );
}
