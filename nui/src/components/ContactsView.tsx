import { useCallback, useState } from 'react';
import type { Contact, UiLabels } from '@/lib/types';
import { translate } from '@/lib/i18n';
import { usePagedList } from '@/lib/usePagedList';
import { Pagination } from './Pagination';
import { TrashIcon } from './icons';

interface ContactsViewProps {
  labels: UiLabels;
  contacts: Contact[];
  onRemove: (contact: Contact) => void;
}

export function ContactsView({ labels, contacts, onRemove }: ContactsViewProps) {
  const t = (key: string) => translate(labels, key);
  const [query, setQuery] = useState('');

  const matches = useCallback(
    (contact: Contact, q: string) => contact.name.toLowerCase().includes(q) || contact.citizenid.toLowerCase().includes(q),
    [],
  );

  const { pageItems, page, pageCount, setPage } = usePagedList(contacts, query, matches, 6);

  return (
    <div className="flex h-full flex-col">
      <div className="mb-4">
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Filter"
          className="w-56 rounded-sm border border-ink/25 bg-paper/60 px-3 py-2 font-body text-sm text-ink placeholder:italic placeholder:text-ink-light/60 focus:border-select focus:outline-none focus:ring-2 focus:ring-select/30"
        />
      </div>

      <div className="overflow-hidden rounded-sm border border-ink/25">
        <table className="w-full border-collapse text-left">
          <thead>
            <tr className="bg-ink text-paper">
              <th className="px-4 py-2 font-display text-xs font-bold uppercase tracking-wider">Name</th>
              <th className="px-4 py-2 font-display text-xs font-bold uppercase tracking-wider">PO Box No.</th>
              <th className="px-4 py-2 font-display text-xs font-bold uppercase tracking-wider">Note</th>
              <th className="w-16 px-4 py-2" />
            </tr>
          </thead>
          <tbody>
            {pageItems.map((contact) => (
              <tr key={contact.citizenid} className="border-t border-ink/15 bg-paper/40">
                <td className="px-4 py-3 font-body text-sm text-ink">{contact.name}</td>
                <td className="px-4 py-3 font-body text-sm text-ink-light">{contact.citizenid}</td>
                <td className="px-4 py-3 font-body text-sm text-ink-light/60">—</td>
                <td className="px-4 py-3">
                  <button
                    type="button"
                    onClick={() => onRemove(contact)}
                    className="rounded p-1.5 text-rust/70 transition hover:bg-rust/10 hover:text-rust"
                    aria-label={t('ui_remove_contact')}
                  >
                    <TrashIcon />
                  </button>
                </td>
              </tr>
            ))}

            {pageItems.length === 0 && (
              <tr>
                <td colSpan={4} className="px-4 py-10 text-center font-body text-sm text-ink-light">
                  {t('ui_empty_addressbook')}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="mt-auto flex items-center justify-between pt-3 text-xs text-ink-light">
        <span>Paging through contacts...</span>
        <Pagination page={page} pageCount={pageCount} onPage={setPage} label={(p, count) => `${p + 1} of ${count}`} />
      </div>
    </div>
  );
}
