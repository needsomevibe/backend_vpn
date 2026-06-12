export function jsonSafe<T>(value: T): T {
  if (typeof value === 'bigint') {
    return value.toString() as T;
  }
  if (value instanceof Date || value === null || value === undefined) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((item) => jsonSafe(item)) as T;
  }
  if (typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, jsonSafe(item)]),
    ) as T;
  }
  return value;
}
