import { useEffect, useMemo, useState, type FormEvent } from 'react';
import type { Contact, JobAlias, JobSender, RecipientCandidate, TelegramMessage, UiLabels } from '@/lib/types';
import { translate } from '@/lib/i18n';
import { getSenderDisplayName } from '@/lib/telegram';
import { FieldLabel, SelectField, TextAreaField, TextField } from './ui';

export const COMPOSE_FORM_ID = 'compose-form';

export interface ComposeDefaults {
  recipient: string;
  recipientLabel?: string;
  subject: string;
  jobSender?: string;
}

interface ComposeViewProps {
  labels: UiLabels;
  players: RecipientCandidate[];
  contacts: Contact[];
  jobSenders: JobSender[];
  enableJobMailboxes: boolean;
  defaults: ComposeDefaults | null;
  onSubmit: (data: { jobSender: string; recipient: string; subject: string; message: string }) => void;
}

export function ComposeView({ labels, players, contacts, jobSenders, enableJobMailboxes, defaults, onSubmit }: ComposeViewProps) {
  const t = (key: string) => translate(labels, key);

  const [jobSender, setJobSender] = useState('');
  const [recipient, setRecipient] = useState('');
  const [recipientLabel, setRecipientLabel] = useState('');
  const [subject, setSubject] = useState('');
  const [message, setMessage] = useState('');
  const [dropdownOpen, setDropdownOpen] = useState(false);

  useEffect(() => {
    if (!defaults) return;
    setJobSender(defaults.jobSender ?? '');
    setRecipient(defaults.recipient);
    setRecipientLabel(defaults.recipientLabel ?? defaults.recipient);
    setSubject(defaults.subject);
    setMessage('');
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [defaults]);

  const choices = useMemo(() => {
    const seen = new Set<string>();
    const list: { value: string; label: string }[] = [];

    for (const contact of contacts) {
      if (seen.has(contact.citizenid)) continue;
      seen.add(contact.citizenid);
      list.push({ value: contact.citizenid, label: contact.name });
    }

    for (const player of players) {
      if (seen.has(player.citizenid)) continue;
      seen.add(player.citizenid);
      list.push({ value: player.citizenid, label: player.job ? player.name : `${player.name} (${player.citizenid})` });
    }

    if (recipient && recipientLabel && !seen.has(recipient)) {
      list.unshift({ value: recipient, label: recipientLabel });
    }

    return list;
  }, [contacts, players, recipient, recipientLabel]);

  const filteredChoices = useMemo(() => {
    const query = recipient.toLowerCase();
    if (!query) return choices.slice(0, 8);
    return choices.filter((c) => c.value.toLowerCase().includes(query) || c.label.toLowerCase().includes(query)).slice(0, 8);
  }, [choices, recipient]);

  const handleSubmit = (event: FormEvent) => {
    event.preventDefault();
    const trimmedRecipient = recipient.trim();
    const trimmedSubject = subject.trim();
    const trimmedMessage = message.trim();
    if (!trimmedRecipient || !trimmedSubject || !trimmedMessage) return;

    onSubmit({ jobSender, recipient: trimmedRecipient, subject: trimmedSubject, message: trimmedMessage });
  };

  const today = useMemo(
    () => new Date().toLocaleDateString(undefined, { day: 'numeric', month: 'numeric', year: 'numeric' }),
    [],
  );

  return (
    <form id={COMPOSE_FORM_ID} onSubmit={handleSubmit} className="flex h-full flex-col gap-4">
      <div className="grid grid-cols-3 gap-4">
        <div className="flex flex-col gap-1.5">
          <FieldLabel htmlFor="compose-sender">{t('ui_sender_label')}</FieldLabel>
          {enableJobMailboxes && jobSenders.length > 0 ? (
            <SelectField id="compose-sender" value={jobSender} onChange={(event) => setJobSender(event.target.value)}>
              <option value="">{t('ui_personal_sender')}</option>
              {jobSenders.map((sender) => (
                <option key={sender.alias} value={sender.alias}>
                  {sender.label}
                </option>
              ))}
            </SelectField>
          ) : (
            <TextField id="compose-sender" value={t('ui_personal_sender')} disabled />
          )}
        </div>

        <div className="relative flex flex-col gap-1.5">
          <FieldLabel htmlFor="compose-recipient">{t('ui_recipient_label')}</FieldLabel>
          <TextField
            id="compose-recipient"
            value={recipient}
            placeholder={t('ui_recipient_placeholder')}
            onChange={(event) => {
              setRecipient(event.target.value);
              setRecipientLabel('');
            }}
            onFocus={() => setDropdownOpen(true)}
            onBlur={() => setTimeout(() => setDropdownOpen(false), 150)}
            autoComplete="off"
          />
          {dropdownOpen && filteredChoices.length > 0 && (
            <div className="scroll-thin absolute left-0 right-0 top-full z-10 mt-1 max-h-44 overflow-y-auto rounded-sm border border-brass bg-[#1a140c] shadow-xl">
              {filteredChoices.map((choice) => (
                <button
                  key={choice.value}
                  type="button"
                  onMouseDown={(event) => {
                    event.preventDefault();
                    setRecipient(choice.value);
                    setRecipientLabel(choice.label);
                    setDropdownOpen(false);
                  }}
                  className="block w-full px-3 py-2 text-left font-body text-sm text-paper hover:bg-brass/20 hover:text-brass-light"
                >
                  {choice.label}
                </button>
              ))}
            </div>
          )}
        </div>

        <div className="flex flex-col gap-1.5">
          <FieldLabel htmlFor="compose-date">{t('ui_date_label')}</FieldLabel>
          <TextField id="compose-date" value={today} disabled />
        </div>
      </div>

      <div className="flex flex-col gap-1.5">
        <FieldLabel htmlFor="compose-subject">{t('ui_subject_label')}</FieldLabel>
        <TextField
          id="compose-subject"
          value={subject}
          onChange={(event) => setSubject(event.target.value)}
          placeholder={t('ui_subject_placeholder')}
        />
      </div>

      <div className="flex flex-1 flex-col gap-1.5">
        <FieldLabel htmlFor="compose-message">{t('ui_message_label')}</FieldLabel>
        <TextAreaField
          id="compose-message"
          value={message}
          onChange={(event) => setMessage(event.target.value)}
          placeholder={t('ui_message_placeholder')}
          className="min-h-[160px] flex-1"
        />
      </div>
    </form>
  );
}

interface MessageReaderProps {
  labels: UiLabels;
  message: TelegramMessage;
  contacts: Contact[];
  jobAliases: Record<string, JobAlias>;
  personalSenderDisplay: 'name' | 'citizenid';
}

export function MessageReader({ labels, message, contacts, jobAliases, personalSenderDisplay }: MessageReaderProps) {
  const t = (key: string) => translate(labels, key);
  const recipientDisplay =
    message.mailbox === 'job' ? message.recipient ?? '' : message.citizenid
      ? contacts.find((c) => c.citizenid === message.citizenid)?.name ?? message.citizenid
      : '';

  return (
    <div className="flex h-full flex-col gap-4">
      <div className="grid grid-cols-3 gap-4">
        <div className="flex flex-col gap-1.5">
          <FieldLabel>{t('ui_from_label')}</FieldLabel>
          <TextField value={getSenderDisplayName(message, contacts, jobAliases, personalSenderDisplay)} disabled />
        </div>
        <div className="flex flex-col gap-1.5">
          <FieldLabel>{t('ui_to_label')}</FieldLabel>
          <TextField value={recipientDisplay} disabled />
        </div>
        <div className="flex flex-col gap-1.5">
          <FieldLabel>{t('ui_date_label')}</FieldLabel>
          <TextField value={message.sentDate} disabled />
        </div>
      </div>

      <div className="flex flex-col gap-1.5">
        <FieldLabel>{t('ui_subject_label')}</FieldLabel>
        <TextField value={message.subject} disabled />
      </div>

      <div className="flex flex-1 flex-col gap-1.5">
        <FieldLabel>{t('ui_message_label')}</FieldLabel>
        <div className="scroll-thin flex-1 overflow-y-auto rounded-sm border border-ink/25 bg-paper/60 px-3 py-2 font-body text-sm leading-relaxed text-ink whitespace-pre-wrap">
          {message.message}
        </div>
      </div>
    </div>
  );
}
