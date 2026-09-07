import { ChevronLeftIcon, ChevronRightIcon, ChevronsLeftIcon, ChevronsRightIcon } from './icons';

interface PaginationProps {
  page: number;
  pageCount: number;
  onPage: (page: number) => void;
  label: (page: number, pageCount: number) => string;
}

export function Pagination({ page, pageCount, onPage, label }: PaginationProps) {
  const atStart = page <= 0;
  const atEnd = page >= pageCount - 1;

  const btn = 'rounded p-1 text-ink/70 transition hover:bg-ink/10 hover:text-ink disabled:opacity-30 disabled:hover:bg-transparent';

  return (
    <div className="flex items-center gap-1 text-sm text-ink/80">
      <button type="button" className={btn} disabled={atStart} onClick={() => onPage(0)} aria-label="First page">
        <ChevronsLeftIcon />
      </button>
      <button type="button" className={btn} disabled={atStart} onClick={() => onPage(page - 1)} aria-label="Previous page">
        <ChevronLeftIcon />
      </button>
      <span className="px-2 font-body">{label(page, pageCount)}</span>
      <button type="button" className={btn} disabled={atEnd} onClick={() => onPage(page + 1)} aria-label="Next page">
        <ChevronRightIcon />
      </button>
      <button
        type="button"
        className={btn}
        disabled={atEnd}
        onClick={() => onPage(pageCount - 1)}
        aria-label="Last page"
      >
        <ChevronsRightIcon />
      </button>
    </div>
  );
}
