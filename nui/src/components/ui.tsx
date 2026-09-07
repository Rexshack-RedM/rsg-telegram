import type { ButtonHTMLAttributes, InputHTMLAttributes, LabelHTMLAttributes, ReactNode, SelectHTMLAttributes, TextareaHTMLAttributes } from 'react';

export function FieldLabel(props: LabelHTMLAttributes<HTMLLabelElement>) {
  return (
    <label
      {...props}
      className={`font-display text-[11px] font-bold uppercase tracking-[0.15em] text-ink-light ${props.className ?? ''}`}
    />
  );
}

const fieldClass =
  'w-full rounded-sm border border-ink/25 bg-paper/60 px-3 py-2 font-body text-sm text-ink placeholder:text-ink-light/50 focus:border-select focus:outline-none focus:ring-2 focus:ring-select/30 disabled:bg-ink/5 disabled:text-ink-light';

export function TextField(props: InputHTMLAttributes<HTMLInputElement>) {
  return <input {...props} className={`${fieldClass} ${props.className ?? ''}`} />;
}

export function TextAreaField(props: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea {...props} className={`${fieldClass} resize-none ${props.className ?? ''}`} />;
}

export function SelectField(props: SelectHTMLAttributes<HTMLSelectElement> & { children: ReactNode }) {
  return (
    <select {...props} className={`${fieldClass} ${props.className ?? ''}`}>
      {props.children}
    </select>
  );
}

export function PrimaryButton(props: ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      {...props}
      type={props.type ?? 'button'}
      className={`flex items-center gap-2 rounded-sm bg-ink px-6 py-3 font-display text-sm font-bold uppercase tracking-[0.1em] text-paper shadow-md transition hover:bg-ink-light disabled:cursor-not-allowed disabled:opacity-50 ${props.className ?? ''}`}
    />
  );
}

export function GhostButton(props: ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      {...props}
      type={props.type ?? 'button'}
      className={`flex items-center gap-2 rounded-sm border border-ink/30 px-4 py-2 font-display text-xs font-bold uppercase tracking-[0.1em] text-ink-light transition hover:border-ink hover:text-ink ${props.className ?? ''}`}
    />
  );
}

export function DangerGhostButton(props: ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      {...props}
      type={props.type ?? 'button'}
      className={`flex items-center gap-2 rounded-sm border border-rust/50 px-4 py-2 font-display text-xs font-bold uppercase tracking-[0.1em] text-rust transition hover:bg-rust hover:text-paper ${props.className ?? ''}`}
    />
  );
}
