export type Mailbox = 'personal' | 'job';

export interface TelegramMessage {
  id: number;
  sender: string;
  sendername?: string;
  recipient?: string;
  citizenid?: string;
  subject: string;
  message: string;
  sentDate: string;
  status: number;
  birdstatus?: number;
  pickedUp?: number;
  mailbox?: Mailbox;
  jobTarget?: string;
}

export interface Contact {
  name: string;
  citizenid: string;
}

export interface RecipientCandidate {
  citizenid: string;
  name: string;
  job?: string;
}

export interface JobSender {
  alias: string;
  label: string;
}

export interface JobAlias {
  label: string;
}

export type UiLabels = Record<string, string>;

export interface OpenUiPayload {
  action: 'openUI';
  defaultTab?: string;
  usingBirdPost?: boolean;
  enableJobMailboxes: boolean;
  personalSenderDisplay: 'name' | 'citizenid';
  jobAliases: Record<string, JobAlias>;
  labels: UiLabels;
  citizenid?: string;
}

export interface LocationCheckResponse {
  atPostOffice: boolean;
  chargePlayer: boolean;
  cost: number;
}

export interface SendMessagePayload {
  jobSender: string;
  recipient: string;
  subject: string;
  message: string;
}

export type NuiIncomingMessage =
  | OpenUiPayload
  | { action: 'closeUI' }
  | { action: 'updateInbox'; messages: TelegramMessage[] }
  | { action: 'updateAddressbook'; contacts: Contact[] }
  | { action: 'updatePlayers'; players: RecipientCandidate[] }
  | { action: 'updateUnreadCount'; count: number }
  | { action: 'messageSent' }
  | { action: 'contactAdded' }
  | { action: 'contactRemoved' };
