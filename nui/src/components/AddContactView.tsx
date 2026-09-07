import { useState, type FormEvent } from 'react';
import type { UiLabels } from '@/lib/types';
import { translate } from '@/lib/i18n';
import { FieldLabel, TextField } from './ui';

export const ADD_CONTACT_FORM_ID = 'add-contact-form';

interface AddContactViewProps {
  labels: UiLabels;
  onSave: (name: string, citizenid: string) => void;
}

export function AddContactView({ labels, onSave }: AddContactViewProps) {
  const t = (key: string) => translate(labels, key);
  const [name, setName] = useState('');
  const [citizenid, setCitizenid] = useState('');

  const handleSubmit = (event: FormEvent) => {
    event.preventDefault();
    const trimmedName = name.trim();
    const trimmedId = citizenid.trim();
    if (!trimmedName || !trimmedId) return;
    onSave(trimmedName, trimmedId);
    setName('');
    setCitizenid('');
  };

  return (
    <form id={ADD_CONTACT_FORM_ID} onSubmit={handleSubmit} className="mx-auto flex max-w-md flex-col gap-5 pt-4">
      <div className="flex flex-col gap-1.5">
        <FieldLabel htmlFor="contact-name">{t('ui_contact_name_label')}</FieldLabel>
        <TextField
          id="contact-name"
          value={name}
          onChange={(event) => setName(event.target.value)}
          placeholder={t('ui_contact_name_placeholder')}
          autoFocus
        />
      </div>

      <div className="flex flex-col gap-1.5">
        <FieldLabel htmlFor="contact-citizenid">{t('ui_contact_citizenid_label')}</FieldLabel>
        <TextField
          id="contact-citizenid"
          value={citizenid}
          onChange={(event) => setCitizenid(event.target.value)}
          placeholder={t('ui_contact_citizenid_placeholder')}
        />
      </div>
    </form>
  );
}
