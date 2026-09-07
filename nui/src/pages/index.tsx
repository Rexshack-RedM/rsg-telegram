import Head from 'next/head';
import { TelegramApp } from '@/components/TelegramApp';

export default function Home() {
  return (
    <>
      <Head>
        <title>Telegram System</title>
      </Head>
      <TelegramApp />
    </>
  );
}
