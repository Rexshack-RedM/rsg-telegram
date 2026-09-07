import type { Contact, JobSender, LocationCheckResponse, RecipientCandidate, TelegramMessage } from './types';

// True only when previewing in a normal browser tab (`npm run dev`) rather than
// inside the RedM/CEF NUI runtime, which never exposes navigator.userAgent as a browser.
export function isMockEnvironment(): boolean {
  return typeof window !== 'undefined' && !(window as { invokeNative?: unknown }).invokeNative;
}

const mockContacts: Contact[] = [
  { name: 'Mia Alderman', citizenid: 'SD2327' },
  { name: 'Elijah Fenwick', citizenid: 'LM4471' },
];

const mockPersonalInbox: TelegramMessage[] = [
  {
    id: 1,
    sender: 'SD2327',
    sendername: 'Mia Alderman',
    citizenid: 'SD1997',
    subject: 'Dear Elijah',
    message:
      'The harvest came in heavy this season. Meet me at the old mill Saturday, before the sun sets.\n\n— Mia',
    sentDate: '25/5/1899 4:11 PM',
    status: 0,
    pickedUp: 1,
  },
  {
    id: 2,
    sender: 'LM4471',
    sendername: 'Elijah Fenwick',
    citizenid: 'SD1997',
    subject: 'Debts owed',
    message: 'You still owe me for the last shipment. Settle up soon.',
    sentDate: '24/5/1899 9:02 AM',
    status: 1,
    pickedUp: 0,
  },
];

const mockJobInbox: TelegramMessage[] = [
  {
    id: 101,
    sender: 'sheriff',
    sendername: 'Sheriff’s Office',
    recipient: 'sheriff',
    subject: 'Wanted: Cattle Rustlers',
    message: 'Reports of stolen cattle near Rhodes. Investigate at first light.',
    sentDate: '25/5/1899 8:00 AM',
    status: 0,
    mailbox: 'job',
    jobTarget: 'sheriff',
  },
];

const mockPlayers: RecipientCandidate[] = [
  { citizenid: 'SD2327', name: 'Mia Alderman' },
  { citizenid: 'LM4471', name: 'Elijah Fenwick' },
  { citizenid: 'VL0093', name: 'Charlotte Reyes' },
];

const mockJobSenders: JobSender[] = [{ alias: 'sheriff', label: 'Sheriff’s Office' }];

export async function mockFetchNui<TResponse>(callback: string, data: object): Promise<TResponse> {
  // eslint-disable-next-line no-console
  console.info('[mock nui]', callback, data);

  switch (callback) {
    case 'getInbox':
      return mockPersonalInbox as unknown as TResponse;
    case 'getJobInbox':
      return mockJobInbox as unknown as TResponse;
    case 'getAddressbook':
      return mockContacts as unknown as TResponse;
    case 'getPlayers':
      return [...mockContacts, ...mockPlayers] as unknown as TResponse;
    case 'getJobSenders':
      return mockJobSenders as unknown as TResponse;
    case 'checkLocation':
      return { atPostOffice: true, chargePlayer: true, cost: 5 } satisfies LocationCheckResponse as unknown as TResponse;
    case 'closeUI':
    case 'sendMessage':
    case 'markAsRead':
    case 'deleteMessage':
    case 'addContact':
    case 'removeContact':
    default:
      return { ok: true } as unknown as TResponse;
  }
}
