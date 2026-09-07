import type { Contact, JobAlias, TelegramMessage } from './types';

export function getContactName(contacts: Contact[], citizenid: string | undefined): string {
  if (!citizenid) return '';
  const contact = contacts.find((c) => c.citizenid === citizenid);
  return contact ? contact.name : citizenid;
}

export function getSenderDisplayName(
  message: TelegramMessage,
  contacts: Contact[],
  jobAliases: Record<string, JobAlias>,
  personalSenderDisplay: 'name' | 'citizenid',
): string {
  if (!message.sender) return '';

  const alias = jobAliases[message.sender];
  if (alias) {
    return message.sendername || alias.label || message.sender;
  }

  if (personalSenderDisplay === 'citizenid') {
    return message.sender;
  }

  const contactName = getContactName(contacts, message.sender);
  if (contactName !== message.sender) {
    return contactName;
  }

  return message.sendername || message.sender;
}

export function isMessageUnread(message: TelegramMessage): boolean {
  return message.status === 0 || message.birdstatus === 0;
}
