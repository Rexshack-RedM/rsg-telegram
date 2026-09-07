import { useCallback, useState } from 'react';
import type { Contact, JobAlias, Mailbox, TelegramMessage, UiLabels } from '@/lib/types';
import { translate } from '@/lib/i18n';
import { getSenderDisplayName, isMessageUnread } from '@/lib/telegram';
import { usePagedList } from '@/lib/usePagedList';
import { Pagination } from './Pagination';
import { CheckIcon, EnvelopeIcon, EnvelopeOpenIcon, RefreshIcon, TrashIcon } from './icons';

interface TelegramsViewProps {
  labels: UiLabels;
  loading: boolean;
  mailbox: Mailbox;
  onChangeMailbox: (mailbox: Mailbox) => void;
  enableJobMailboxes: boolean;
  messages: TelegramMessage[];
  contacts: Contact[];
  jobAliases: Record<string, JobAlias>;
  personalSenderDisplay: 'name' | 'citizenid';
  onOpen: (message: TelegramMessage) => void;
  onMarkRead: (message: TelegramMessage) => void;
  onDelete: (message: TelegramMessage) => void;
  onRefresh: () => void;
}

export function TelegramsView({
  labels,
  loading,
  mailbox,
  onChangeMailbox,
  enableJobMailboxes,
  messages,
  contacts,
  jobAliases,
  personalSenderDisplay,
  onOpen,
  onMarkRead,
  onDelete,
  onRefresh,
}: TelegramsViewProps) {
  const t = (key: string, replacements?: Record<string, string | number>) => translate(labels, key, replacements);
  const [query, setQuery] = useState('');

  const matches = useCallback(
    (message: TelegramMessage, q: string) => {
      const sender = getSenderDisplayName(message, contacts, jobAliases, personalSenderDisplay).toLowerCase();
      return message.subject.toLowerCase().includes(q) || sender.includes(q);
    },
    [contacts, jobAliases, personalSenderDisplay],
  );

  const { pageItems, page, pageCount, setPage, total } = usePagedList(messages, query, matches, 6);

  return (
    <div className="flex h-full flex-col">
      <div className="mb-4 flex items-center gap-3">
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Filter"
          className="w-56 rounded-sm border border-ink/25 bg-paper/60 px-3 py-2 font-body text-sm text-ink placeholder:italic placeholder:text-ink-light/60 focus:border-select focus:outline-none focus:ring-2 focus:ring-select/30"
        />

        {enableJobMailboxes && (
          <div className="flex overflow-hidden rounded-sm border border-ink/30">
            <button
              type="button"
              onClick={() => onChangeMailbox('personal')}
              className={`px-3 py-2 font-display text-xs font-bold uppercase tracking-wide ${
                mailbox === 'personal' ? 'bg-select text-paper' : 'bg-transparent text-ink-light hover:text-ink'
              }`}
            >
              {t('ui_inbox')}
            </button>
            <button
              type="button"
              onClick={() => onChangeMailbox('job')}
              className={`px-3 py-2 font-display text-xs font-bold uppercase tracking-wide ${
                mailbox === 'job' ? 'bg-select text-paper' : 'bg-transparent text-ink-light hover:text-ink'
              }`}
            >
              {t('ui_job_inbox')}
            </button>
          </div>
        )}

        <button
          type="button"
          onClick={onRefresh}
          className="ml-auto rounded-sm p-2 text-ink-light transition hover:bg-ink/10 hover:text-ink"
          aria-label="Refresh"
        >
          <RefreshIcon className={loading ? 'animate-spin' : ''} />
        </button>
      </div>

      <div className="overflow-hidden rounded-sm border border-ink/25">
        <table className="w-full border-collapse text-left">
          <thead>
            <tr className="bg-ink text-paper">
              <th className="px-4 py-2 font-display text-xs font-bold uppercase tracking-wider">Title</th>
              <th className="px-4 py-2 font-display text-xs font-bold uppercase tracking-wider">Sender</th>
              <th className="px-4 py-2 font-display text-xs font-bold uppercase tracking-wider">Timestamp</th>
              <th className="w-20 px-4 py-2" />
            </tr>
          </thead>
          <tbody>
            {pageItems.map((message) => {
              const unread = isMessageUnread(message);
              const notPickedUp = message.pickedUp === 0;

              return (
                <tr
                  key={message.id}
                  className="cursor-pointer border-t border-ink/15 bg-paper/40 transition hover:bg-brass-light/30"
                  onClick={() => onOpen(message)}
                >
                  <td className="px-4 py-3 font-body text-sm text-ink">
                    <div className="flex items-center gap-2">
                      {unread ? <EnvelopeIcon className="shrink-0 text-brass" /> : <EnvelopeOpenIcon className="shrink-0 text-ink-light" />}
                      <span className={unread ? 'font-bold' : ''}>{message.subject}</span>
                      {notPickedUp && (
                        <span className="rounded-sm border border-brass px-1.5 py-0.5 text-[10px] font-bold uppercase text-brass">
                          {t('ui_at_post_office')}
                        </span>
                      )}
                      {mailbox === 'job' && (
                        <span className="rounded-sm border border-brass px-1.5 py-0.5 text-[10px] font-bold uppercase text-brass">
                          {t('ui_job_badge')}
                        </span>
                      )}
                    </div>
                  </td>
                  <td className="px-4 py-3 font-body text-sm text-ink-light">
                    {getSenderDisplayName(message, contacts, jobAliases, personalSenderDisplay)}
                  </td>
                  <td className="px-4 py-3 font-body text-xs text-ink-light">{message.sentDate}</td>
                  <td className="px-4 py-3">
                    <div className="flex items-center justify-end gap-1" onClick={(event) => event.stopPropagation()}>
                      {unread && (
                        <button
                          type="button"
                          onClick={() => onMarkRead(message)}
                          className="rounded p-1.5 text-ink-light transition hover:bg-ink/10 hover:text-ink"
                          aria-label="Mark as read"
                        >
                          <CheckIcon />
                        </button>
                      )}
                      <button
                        type="button"
                        onClick={() => onDelete(message)}
                        className="rounded p-1.5 text-rust/70 transition hover:bg-rust/10 hover:text-rust"
                        aria-label="Delete"
                      >
                        <TrashIcon />
                      </button>
                    </div>
                  </td>
                </tr>
              );
            })}

            {pageItems.length === 0 && (
              <tr>
                <td colSpan={4} className="px-4 py-10 text-center font-body text-sm text-ink-light">
                  {mailbox === 'job' ? t('ui_empty_job_inbox') : t('ui_empty_inbox')}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="mt-auto flex items-center justify-between pt-3 text-xs text-ink-light">
        <span>Paging through telegrams...</span>
        <Pagination page={page} pageCount={pageCount} onPage={setPage} label={(p, count) => `${p + 1} of ${count}`} />
      </div>
      <span className="sr-only">{total}</span>
    </div>
  );
}
