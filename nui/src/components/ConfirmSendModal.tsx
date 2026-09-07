import type { LocationCheckResponse, UiLabels } from '@/lib/types';
import { translate } from '@/lib/i18n';
import { GhostButton, PrimaryButton } from './ui';
import { PaperPlaneIcon } from './icons';

interface ConfirmSendModalProps {
  labels: UiLabels;
  location: LocationCheckResponse | null;
  onConfirm: () => void;
  onCancel: () => void;
}

export function ConfirmSendModal({ labels, location, onConfirm, onCancel }: ConfirmSendModalProps) {
  const t = (key: string, replacements?: Record<string, string | number>) => translate(labels, key, replacements);

  const showBirdWarning = location ? !location.atPostOffice : false;
  const showCostWarning = location ? location.atPostOffice && location.chargePlayer : false;

  return (
    <div className="fixed inset-0 z-20 flex items-center justify-center bg-black/60">
      <div className="paper-texture relative w-[420px] rounded-sm p-7 shadow-2xl ring-1 ring-black/40">
        <h2 className="font-display text-xl font-bold text-ink">{t('ui_confirm_send_title')}</h2>
        <p className="mt-3 font-body text-sm leading-relaxed text-ink-light">{t('ui_confirm_send_text')}</p>

        {showBirdWarning && (
          <div className="mt-4 rounded-sm border-l-4 border-brass bg-brass/10 p-3 font-body text-xs text-ink">
            <strong className="font-bold">{t('ui_note_label')}</strong> {t('ui_birdpost_warning')}
          </div>
        )}

        {showCostWarning && (
          <div className="mt-4 rounded-sm border-l-4 border-brass bg-brass/10 p-3 font-body text-xs text-ink">
            <strong className="font-bold">{t('ui_cost_label')}</strong> {t('ui_cost_warning')} {location?.cost.toFixed(2)}.
          </div>
        )}

        <div className="mt-6 flex justify-end gap-3">
          <GhostButton onClick={onCancel}>{t('ui_cancel')}</GhostButton>
          <PrimaryButton onClick={onConfirm}>
            <PaperPlaneIcon />
            {t('ui_send_message')}
          </PrimaryButton>
        </div>
      </div>
    </div>
  );
}
