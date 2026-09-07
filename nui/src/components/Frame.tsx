import type { ReactNode } from 'react';
import { BellIcon, CloseIcon } from './icons';

export interface NavTab {
  key: string;
  label: string;
  onClick: () => void;
  active: boolean;
}

interface FrameProps {
  animState: 'in' | 'out';
  eyebrow: ReactNode;
  topRight: ReactNode;
  tagline: string;
  navTabs: NavTab[];
  unreadCount: number;
  onBell: () => void;
  onClose: () => void;
  footerLeft: string;
  footerButton: ReactNode;
  children: ReactNode;
}

export function Frame({
  animState,
  eyebrow,
  topRight,
  tagline,
  navTabs,
  unreadCount,
  onBell,
  onClose,
  footerLeft,
  footerButton,
  children,
}: FrameProps) {
  return (
    <div className="fixed inset-0 flex items-center justify-center">
      <div
        className={`paper-texture relative flex flex-col rounded-sm shadow-[0_25px_60px_rgba(0,0,0,0.55)] ring-1 ring-black/40 ${animState === 'in' ? 'anim-in' : 'anim-out'}`}
        style={{ width: 'min(920px, 92vw)', minHeight: 600, maxHeight: '82vh' }}
      >
        <div className="absolute right-4 top-4 z-10 flex items-center gap-2">
          <button
            type="button"
            onClick={onBell}
            aria-label={unreadCount > 0 ? `${unreadCount} unread telegrams` : 'Telegrams'}
            className={`flex h-8 items-center gap-1.5 rounded-full border px-2.5 transition-colors ${
              unreadCount > 0
                ? 'border-rust/50 bg-rust/10 text-rust hover:bg-rust hover:text-paper'
                : 'border-ink/25 text-ink-light hover:border-select hover:bg-select hover:text-paper'
            }`}
          >
            <BellIcon width={14} height={14} />
            {unreadCount > 0 && (
              <span className="font-display text-xs font-bold leading-none">{unreadCount > 99 ? '99+' : unreadCount}</span>
            )}
          </button>

          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="flex h-8 w-8 items-center justify-center rounded-full border border-ink/25 text-ink-light transition-colors hover:border-rust hover:bg-rust hover:text-paper"
          >
            <CloseIcon width={14} height={14} />
          </button>
        </div>

        <div className="relative flex items-start justify-between gap-6 px-9 pt-7">
          <div className="flex-1">{eyebrow}</div>
          <div className="mr-20 shrink-0 text-right">{topRight}</div>
        </div>

        <div className="px-9">
          <div className="flex items-baseline justify-between rule-line pb-3">
            <h1 className="font-display text-[34px] font-black tracking-wide text-ink">TELEGRAM</h1>
            <p className="max-w-[60%] text-right font-body text-[11px] leading-snug text-ink-light">{tagline}</p>
          </div>
        </div>

        <div className="flex items-center gap-3 px-9 pb-1 pt-4">
          <div className="flex overflow-hidden rounded-sm border border-ink/30">
            {navTabs.map((tab) => (
              <button
                key={tab.key}
                type="button"
                onClick={tab.onClick}
                className={`px-4 py-2 font-display text-xs font-bold uppercase tracking-[0.1em] transition-colors ${
                  tab.active ? 'bg-select text-paper' : 'bg-transparent text-ink-light hover:bg-ink/5 hover:text-ink'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>
        </div>

        <div className="scroll-thin flex-1 overflow-y-auto px-9 py-4">{children}</div>

        <div className="rule-line mx-9 mb-0" />
        <div className="flex items-center justify-between gap-4 px-9 py-5">
          <p className="max-w-[55%] font-body text-[11px] leading-snug text-ink-light">{footerLeft}</p>
          {footerButton}
        </div>
      </div>
    </div>
  );
}
