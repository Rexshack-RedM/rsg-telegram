import { useEffect, useMemo, useState } from 'react';

export function usePagedList<T>(items: T[], query: string, matches: (item: T, query: string) => boolean, pageSize = 6) {
  const normalizedQuery = query.trim().toLowerCase();

  const filtered = useMemo(() => {
    if (!normalizedQuery) return items;
    return items.filter((item) => matches(item, normalizedQuery));
  }, [items, normalizedQuery, matches]);

  const [page, setPage] = useState(0);

  useEffect(() => {
    setPage(0);
  }, [normalizedQuery, items.length]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / pageSize));
  const currentPage = Math.min(page, pageCount - 1);
  const start = currentPage * pageSize;
  const pageItems = filtered.slice(start, start + pageSize);

  return { pageItems, page: currentPage, pageCount, setPage, total: filtered.length };
}
