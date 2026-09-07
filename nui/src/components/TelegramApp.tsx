import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { fetchNui } from '@/lib/nui';
import { isMockEnvironment } from '@/lib/mock';
import { defaultLabels } from '@/lib/defaultLabels';
import { translate } from '@/lib/i18n';
import type {
  Contact,
  JobAlias,
  JobSender,
  LocationCheckResponse,
  Mailbox,
  NuiIncomingMessage,
  OpenUiPayload,
  RecipientCandidate,
  SendMessagePayload,
  TelegramMessage,
} from '@/lib/types';
import { Frame, type NavTab } from './Frame';
import { TelegramsView } from './TelegramsView';
import { ContactsView } from './ContactsView';
import { ComposeView, MessageReader, COMPOSE_FORM_ID, type ComposeDefaults } from './ComposeView';
import { AddContactView, ADD_CONTACT_FORM_ID } from './AddContactView';
import { ConfirmSendModal } from './ConfirmSendModal';
import { PrimaryButton, GhostButton, DangerGhostButton } from './ui';
import { PaperPlaneIcon, PlusPersonIcon, ReplyIcon, TrashIcon } from './icons';

type Screen = 'telegrams' | 'contacts' | 'compose' | 'view-message' | 'add-contact';
type RootScreen = 'telegrams' | 'contacts';

export function TelegramApp() {
  const [visible, setVisible] = useState(false);
  const [animState, setAnimState] = useState<'in' | 'out'>('in');
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const [labels, setLabels] = useState(defaultLabels);
  const [enableJobMailboxes, setEnableJobMailboxes] = useState(true);
  const [personalSenderDisplay, setPersonalSenderDisplay] = useState<'name' | 'citizenid'>('name');
  const [jobAliases, setJobAliases] = useState<Record<string, JobAlias>>({});
  const [playerCitizenId, setPlayerCitizenId] = useState('');

  const [screen, setScreen] = useState<Screen>('telegrams');
  const [rootScreen, setRootScreen] = useState<RootScreen>('telegrams');
  const [mailbox, setMailbox] = useState<Mailbox>('personal');

  const [personalMessages, setPersonalMessages] = useState<TelegramMessage[]>([]);
  const [jobMessages, setJobMessages] = useState<TelegramMessage[]>([]);
  const [contacts, setContacts] = useState<Contact[]>([]);
  const [players, setPlayers] = useState<RecipientCandidate[]>([]);
  const [jobSenders, setJobSenders] = useState<JobSender[]>([]);
  const [loadingInbox, setLoadingInbox] = useState(false);
  const [unreadOverride, setUnreadOverride] = useState<number | null>(null);

  const [selectedMessage, setSelectedMessage] = useState<TelegramMessage | null>(null);
  const [composeDefaults, setComposeDefaults] = useState<ComposeDefaults | null>(null);

  const [confirmOpen, setConfirmOpen] = useState(false);
  const [pendingSend, setPendingSend] = useState<SendMessagePayload | null>(null);
  const [locationCheck, setLocationCheck] = useState<LocationCheckResponse | null>(null);

  const t = useCallback((key: string, replacements?: Record<string, string | number>) => translate(labels, key, replacements), [labels]);

  const loadInboxFor = useCallback(async (target: Mailbox) => {
    setLoadingInbox(true);
    try {
      const contactList = await fetchNui<Contact[]>('getAddressbook');
      setContacts(contactList ?? []);

      if (target === 'job') {
        const jobList = await fetchNui<TelegramMessage[]>('getJobInbox');
        setJobMessages(jobList ?? []);
      } else {
        const list = await fetchNui<TelegramMessage[]>('getInbox');
        setPersonalMessages(list ?? []);
      }
    } finally {
      setLoadingInbox(false);
    }
  }, []);

  const loadContacts = useCallback(async () => {
    const contactList = await fetchNui<Contact[]>('getAddressbook');
    setContacts(contactList ?? []);
  }, []);

  const loadRecipients = useCallback(
    async (jobsEnabled: boolean) => {
      const playerList = await fetchNui<RecipientCandidate[]>('getPlayers');
      setPlayers(playerList ?? []);

      if (jobsEnabled) {
        const senders = await fetchNui<JobSender[]>('getJobSenders');
        setJobSenders(senders ?? []);
      } else {
        setJobSenders([]);
      }
    },
    [],
  );

  const openTelegrams = useCallback(
    (target: Mailbox = 'personal') => {
      setScreen('telegrams');
      setRootScreen('telegrams');
      setMailbox(target);
      void loadInboxFor(target);
    },
    [loadInboxFor],
  );

  const openContacts = useCallback(() => {
    setScreen('contacts');
    setRootScreen('contacts');
    void loadContacts();
  }, [loadContacts]);

  const openCompose = useCallback(
    (defaults: ComposeDefaults | null, root: RootScreen = 'telegrams') => {
      setComposeDefaults(defaults ?? { recipient: '', subject: '', jobSender: '' });
      setScreen('compose');
      setRootScreen(root);
      void loadRecipients(enableJobMailboxes);
    },
    [enableJobMailboxes, loadRecipients],
  );

  const openAddContact = useCallback(() => {
    setScreen('add-contact');
    setRootScreen('contacts');
  }, []);

  const closeUi = useCallback(() => {
    setAnimState('out');
    if (closeTimer.current) clearTimeout(closeTimer.current);
    closeTimer.current = setTimeout(() => {
      setVisible(false);
      void fetchNui('closeUI');
    }, 200);
  }, []);

  const applyOpenPayload = useCallback(
    (payload: OpenUiPayload) => {
      setLabels(payload.labels && Object.keys(payload.labels).length > 0 ? payload.labels : defaultLabels);
      setEnableJobMailboxes(payload.enableJobMailboxes !== false);
      setPersonalSenderDisplay(payload.personalSenderDisplay === 'citizenid' ? 'citizenid' : 'name');
      setJobAliases(payload.jobAliases ?? {});
      if (payload.citizenid) setPlayerCitizenId(payload.citizenid);

      if (closeTimer.current) clearTimeout(closeTimer.current);
      setAnimState('in');
      setVisible(true);

      const jobsEnabled = payload.enableJobMailboxes !== false;
      let tab = payload.defaultTab;
      if (tab === 'job-inbox' && !jobsEnabled) tab = 'inbox';

      if (tab === 'job-inbox') {
        setScreen('telegrams');
        setRootScreen('telegrams');
        setMailbox('job');
        void loadInboxFor('job');
      } else if (tab === 'new-message') {
        setComposeDefaults({ recipient: '', subject: '', jobSender: '' });
        setScreen('compose');
        setRootScreen('telegrams');
        void loadRecipients(jobsEnabled);
      } else if (tab === 'addressbook') {
        setScreen('contacts');
        setRootScreen('contacts');
        void loadContacts();
      } else {
        setScreen('telegrams');
        setRootScreen('telegrams');
        setMailbox('personal');
        void loadInboxFor('personal');
      }
    },
    [loadContacts, loadInboxFor, loadRecipients],
  );

  // NUI message bridge from the Lua client.
  useEffect(() => {
    function handleMessage(event: MessageEvent<NuiIncomingMessage>) {
      const data = event.data;
      if (!data || typeof (data as { action?: string }).action !== 'string') return;

      switch (data.action) {
        case 'openUI':
          applyOpenPayload(data);
          break;
        case 'closeUI':
          closeUi();
          break;
        case 'updateInbox':
          setPersonalMessages(data.messages ?? []);
          break;
        case 'updateAddressbook':
          setContacts(data.contacts ?? []);
          break;
        case 'updatePlayers':
          setPlayers(data.players ?? []);
          break;
        case 'updateUnreadCount':
          setUnreadOverride(data.count ?? 0);
          break;
        case 'messageSent':
          openTelegrams('personal');
          break;
        case 'contactAdded':
        case 'contactRemoved':
          if (screen === 'contacts') void loadContacts();
          break;
        default:
          break;
      }
    }

    window.addEventListener('message', handleMessage);
    return () => window.removeEventListener('message', handleMessage);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [applyOpenPayload, closeUi, openTelegrams, loadContacts, screen]);

  // Preview harness: outside the CEF runtime, simulate the Lua `openUI` call.
  useEffect(() => {
    if (!isMockEnvironment()) return;
    applyOpenPayload({
      action: 'openUI',
      enableJobMailboxes: true,
      personalSenderDisplay: 'name',
      jobAliases: { sheriff: { label: 'Sheriff’s Office' } },
      labels: defaultLabels,
      citizenid: 'SD1997',
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Esc closes the topmost layer: confirm dialog, then sub-screen, then the whole UI.
  useEffect(() => {
    function handleKey(event: KeyboardEvent) {
      if (event.key !== 'Escape') return;
      if (confirmOpen) {
        setConfirmOpen(false);
        setPendingSend(null);
        return;
      }
      if (screen !== 'telegrams' && screen !== 'contacts') {
        if (rootScreen === 'contacts') openContacts();
        else openTelegrams(mailbox);
        return;
      }
      closeUi();
    }

    window.addEventListener('keyup', handleKey);
    return () => window.removeEventListener('keyup', handleKey);
  }, [confirmOpen, screen, rootScreen, mailbox, openContacts, openTelegrams, closeUi]);

  const handleOpenMessage = useCallback((message: TelegramMessage) => {
    setSelectedMessage(message);
    setScreen('view-message');
    void fetchNui('markAsRead', { id: message.id });

    const updater = message.mailbox === 'job' ? setJobMessages : setPersonalMessages;
    updater((list) => list.map((m) => (m.id === message.id ? { ...m, status: 1, birdstatus: 1 } : m)));
  }, []);

  const handleMarkRead = useCallback((message: TelegramMessage) => {
    void fetchNui('markAsRead', { id: message.id });
    const updater = mailbox === 'job' ? setJobMessages : setPersonalMessages;
    updater((list) => list.map((m) => (m.id === message.id ? { ...m, status: 1, birdstatus: 1 } : m)));
  }, [mailbox]);

  const handleDeleteMessage = useCallback(
    (message: TelegramMessage) => {
      void fetchNui('deleteMessage', { id: message.id });
      const updater = (message.mailbox ?? mailbox) === 'job' ? setJobMessages : setPersonalMessages;
      updater((list) => list.filter((m) => m.id !== message.id));

      if (screen === 'view-message') {
        openTelegrams((message.mailbox ?? mailbox) as Mailbox);
      }
    },
    [mailbox, screen, openTelegrams],
  );

  const handleReply = useCallback((message: TelegramMessage) => {
    const replyPrefix = t('ui_reply_subject_prefix');
    const alreadyPrefixed = message.subject?.toLowerCase().startsWith(replyPrefix.toLowerCase());
    const replySubject = alreadyPrefixed ? message.subject : `${replyPrefix} ${message.subject ?? ''}`.trim();
    const jobReplySender = message.mailbox === 'job' ? message.jobTarget ?? '' : '';

    openCompose(
      {
        recipient: message.sender,
        recipientLabel: message.sendername || message.sender,
        subject: replySubject,
        jobSender: jobReplySender,
      },
      'telegrams',
    );
  }, [t, openCompose]);

  const handleSubmitCompose = useCallback(async (data: { jobSender: string; recipient: string; subject: string; message: string }) => {
    setPendingSend(data);
    const location = await fetchNui<LocationCheckResponse>('checkLocation');
    setLocationCheck(location);
    setConfirmOpen(true);
  }, []);

  const handleConfirmSend = useCallback(() => {
    if (!pendingSend) return;
    void fetchNui('sendMessage', pendingSend);
    setConfirmOpen(false);
    setPendingSend(null);
    openTelegrams('personal');
  }, [pendingSend, openTelegrams]);

  const handleCancelSend = useCallback(() => {
    setConfirmOpen(false);
    setPendingSend(null);
  }, []);

  const handleSaveContact = useCallback((name: string, citizenid: string) => {
    void fetchNui('addContact', { name, citizenid });
    setContacts((list) => [...list, { name, citizenid }]);
    setScreen('contacts');
  }, []);

  const handleRemoveContact = useCallback((contact: Contact) => {
    void fetchNui('removeContact', { citizenid: contact.citizenid });
    setContacts((list) => list.filter((c) => c.citizenid !== contact.citizenid));
  }, []);

  if (!visible) return null;

  const activeMessages = mailbox === 'job' ? jobMessages : personalMessages;
  const unreadCount =
    unreadOverride ?? personalMessages.filter((m) => m.status === 0 || m.birdstatus === 0).length;

  const navTabs: NavTab[] = [
    {
      key: 'telegrams',
      label: t('ui_inbox'),
      active: rootScreen === 'telegrams',
      onClick: () => openTelegrams('personal'),
    },
    {
      key: 'contacts',
      label: t('ui_addressbook'),
      active: rootScreen === 'contacts',
      onClick: openContacts,
    },
  ];

  const eyebrow = (
    <div>
      <div className="flex gap-4 font-display text-[11px] font-bold uppercase tracking-[0.2em] text-ink-light">
        <span className="rule-line pb-1">Saint Denis</span>
        <span className="rule-line pb-1">Lemoyne</span>
        <span className="rule-line pb-1">Postal Service</span>
      </div>
      <p className="mt-2 max-w-sm font-body text-[10px] leading-snug text-ink-light/80">
        These telegrams are sent and received subject to the Post and Telegraph Act. The time received is stamped at
        the office of delivery.
      </p>
    </div>
  );

  const topRight = (() => {
    if (screen === 'compose') {
      return (
        <div className="max-w-[220px]">
          <p className="font-display text-[11px] font-bold uppercase tracking-[0.15em] text-rust">Service</p>
          <p className="mt-1 font-body text-[10px] leading-snug text-ink-light">
            {locationCheck?.atPostOffice === false
              ? t('ui_birdpost_warning')
              : locationCheck?.chargePlayer
                ? `${t('ui_cost_warning')} ${locationCheck.cost.toFixed(2)}.`
                : 'Sending from a Post Office is free of charge.'}
          </p>
        </div>
      );
    }

    return (
      <div>
        <p className="font-display text-[11px] font-bold uppercase tracking-[0.15em] text-ink-light">Telegram No.</p>
        <p className="whitespace-nowrap font-display text-3xl font-black text-rust">{playerCitizenId || '—'}</p>
      </div>
    );
  })();

  const tagline =
    'This company TRANSMITS and DELIVERS messages only on conditions limiting its liability, subject to the terms printed on the back of this note.';

  let content: ReactNode = null;
  let footerLeft = 'The postal company’s system reaches all important points and via commercial cables, all the world.';
  let footerButton: ReactNode = null;

  if (screen === 'telegrams') {
    content = (
      <TelegramsView
        labels={labels}
        loading={loadingInbox}
        mailbox={mailbox}
        onChangeMailbox={(m) => openTelegrams(m)}
        enableJobMailboxes={enableJobMailboxes}
        messages={activeMessages}
        contacts={contacts}
        jobAliases={jobAliases}
        personalSenderDisplay={personalSenderDisplay}
        onOpen={handleOpenMessage}
        onMarkRead={handleMarkRead}
        onDelete={handleDeleteMessage}
        onRefresh={() => loadInboxFor(mailbox)}
      />
    );
    footerButton = (
      <PrimaryButton onClick={() => openCompose(null, 'telegrams')}>
        <PaperPlaneIcon />
        Compose Telegram
      </PrimaryButton>
    );
  } else if (screen === 'contacts') {
    content = <ContactsView labels={labels} contacts={contacts} onRemove={handleRemoveContact} />;
    footerButton = (
      <PrimaryButton onClick={openAddContact}>
        <PlusPersonIcon />
        {t('ui_add_new_contact')}
      </PrimaryButton>
    );
  } else if (screen === 'compose') {
    content = (
      <ComposeView
        labels={labels}
        players={players}
        contacts={contacts}
        jobSenders={jobSenders}
        enableJobMailboxes={enableJobMailboxes}
        defaults={composeDefaults}
        onSubmit={handleSubmitCompose}
      />
    );
    footerButton = (
      <PrimaryButton type="submit" form={COMPOSE_FORM_ID}>
        <PaperPlaneIcon />
        {t('ui_send_message')}
      </PrimaryButton>
    );
  } else if (screen === 'view-message' && selectedMessage) {
    content = (
      <MessageReader
        labels={labels}
        message={selectedMessage}
        contacts={contacts}
        jobAliases={jobAliases}
        personalSenderDisplay={personalSenderDisplay}
      />
    );
    footerLeft = '';
    footerButton = (
      <div className="flex gap-3">
        <DangerGhostButton onClick={() => handleDeleteMessage(selectedMessage)}>
          <TrashIcon />
          {t('ui_delete')}
        </DangerGhostButton>
        <GhostButton onClick={() => handleReply(selectedMessage)}>
          <ReplyIcon />
          {t('ui_reply')}
        </GhostButton>
      </div>
    );
  } else if (screen === 'add-contact') {
    content = <AddContactView labels={labels} onSave={handleSaveContact} />;
    footerButton = (
      <PrimaryButton type="submit" form={ADD_CONTACT_FORM_ID}>
        <PlusPersonIcon />
        {t('ui_save_contact')}
      </PrimaryButton>
    );
  }

  return (
    <>
      <Frame
        animState={animState}
        eyebrow={eyebrow}
        topRight={topRight}
        tagline={tagline}
        navTabs={navTabs}
        unreadCount={unreadCount}
        onBell={() => openTelegrams('personal')}
        onClose={closeUi}
        footerLeft={footerLeft}
        footerButton={footerButton}
      >
        {content}
      </Frame>

      {confirmOpen && (
        <ConfirmSendModal labels={labels} location={locationCheck} onConfirm={handleConfirmSend} onCancel={handleCancelSend} />
      )}
    </>
  );
}
