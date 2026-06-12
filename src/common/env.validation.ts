type Env = Record<string, string | undefined>;

const required = [
  'DATABASE_URL',
  'JWT_ACCESS_SECRET',
  'JWT_REFRESH_SECRET',
  'REMNAWAVE_BASE_URL',
  'REMNAWAVE_API_TOKEN',
  'REMNAWAVE_INTERNAL_SQUAD_UUID',
  'SUBSCRIPTION_BASE_URL',
];

export function validateEnv(config: Env) {
  const missing = required.filter((key) => !config[key]);
  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
  }
  return {
    ...config,
    PORT: Number(config.PORT ?? 3000),
  };
}
