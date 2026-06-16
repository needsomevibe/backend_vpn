import { HttpService } from '@nestjs/axios';
import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AxiosError, AxiosRequestConfig } from 'axios';
import { firstValueFrom } from 'rxjs';
import {
  CreateRemnawaveUserInput,
  RemnawaveUsage,
  RemnawaveUser,
  UpdateRemnawaveUserInput,
} from './remnawave.types';

type AnyRecord = Record<string, unknown>;

/** Error carrying the upstream Remnawave status code and error code (e.g. `A030`).
 * Extends `ServiceUnavailableException` so unhandled failures still surface as 503,
 * while callers can inspect `errorCode` to handle idempotent cases. */
export class RemnawaveApiError extends ServiceUnavailableException {
  constructor(
    readonly upstreamStatus: number | undefined,
    readonly errorCode: string | undefined,
  ) {
    super('Remnawave API is unavailable');
  }
}

@Injectable()
export class RemnawaveService {
  private readonly logger = new Logger(RemnawaveService.name);
  private readonly baseUrl: string;
  private readonly token: string;
  private readonly subscriptionBaseUrl: string;
  private readonly internalSquadUuid: string;

  constructor(
    private readonly http: HttpService,
    config: ConfigService,
  ) {
    this.baseUrl = config.getOrThrow<string>('REMNAWAVE_BASE_URL').replace(/\/$/, '');
    this.token = config.getOrThrow<string>('REMNAWAVE_API_TOKEN');
    this.internalSquadUuid = config.getOrThrow<string>('REMNAWAVE_INTERNAL_SQUAD_UUID');
    this.subscriptionBaseUrl = config
      .getOrThrow<string>('SUBSCRIPTION_BASE_URL')
      .replace(/\/$/, '');
  }

  async createUser(input: CreateRemnawaveUserInput): Promise<RemnawaveUser> {
    const response = await this.request<AnyRecord>({
      method: 'POST',
      url: '/api/users',
      data: {
        username: input.username,
        status: 'ACTIVE',
        trafficLimitBytes: Number(input.trafficLimitBytes),
        trafficLimitStrategy: 'NO_RESET',
        expireAt: input.expiresAt.toISOString(),
        activeInternalSquads: [this.internalSquadUuid],
      },
    });
    return this.normalizeUser(response, input.username);
  }

  async getUserByUuid(uuid: string): Promise<RemnawaveUser> {
    const response = await this.request<AnyRecord>({
      method: 'GET',
      url: `/api/users/${uuid}`,
    });
    return this.normalizeUser(response);
  }

  async updateUser(uuid: string, input: UpdateRemnawaveUserInput): Promise<RemnawaveUser> {
    // Remnawave's update endpoint is `PATCH /api/users` with `uuid` in the body —
    // not `/api/users/{uuid}` (that path returns 404).
    const data: AnyRecord = { uuid };
    if (input.username !== undefined) data.username = input.username;
    if (input.status !== undefined) data.status = input.status;
    if (input.trafficLimitBytes !== undefined) {
      data.trafficLimitBytes = Number(input.trafficLimitBytes);
    }
    if (input.expiresAt !== undefined) data.expireAt = input.expiresAt.toISOString();

    const response = await this.request<AnyRecord>({
      method: 'PATCH',
      url: '/api/users',
      data,
    });
    return this.normalizeUser(response);
  }

  async enableUser(uuid: string): Promise<RemnawaveUser> {
    return this.updateStatus(uuid, 'ACTIVE', `/api/users/${uuid}/actions/enable`);
  }

  async disableUser(uuid: string): Promise<RemnawaveUser> {
    return this.updateStatus(uuid, 'DISABLED', `/api/users/${uuid}/actions/disable`);
  }

  async resetTraffic(uuid: string): Promise<void> {
    await this.request({
      method: 'POST',
      url: `/api/users/${uuid}/actions/reset-traffic`,
    });
  }

  async revokeSubscription(uuid: string): Promise<void> {
    await this.request({
      method: 'POST',
      url: `/api/users/${uuid}/actions/revoke`,
      data: { revokeOnlyPasswords: false },
    });
  }

  async getUserUsage(uuid: string): Promise<RemnawaveUsage> {
    // The cumulative used traffic and last node live on the user object.
    // (`/api/bandwidth-stats/users/{uuid}` returns per-node usage over a date
    // range, not the cumulative total, and requires `start`/`end` params.)
    const user = await this.getUserByUuid(uuid);
    return {
      usedTrafficBytes: user.usedTrafficBytes,
      nodeLocation: user.lastConnectedNode?.country ?? user.lastConnectedNode?.name,
    };
  }

  private async updateStatus(uuid: string, status: 'ACTIVE' | 'DISABLED', actionUrl: string) {
    try {
      const response = await this.request<AnyRecord>({ method: 'POST', url: actionUrl });
      return this.normalizeUser(response);
    } catch (error) {
      // Enabling an already-enabled user (or disabling an already-disabled one)
      // is a no-op success, not a failure. Remnawave returns 400 A030/A029.
      if (this.isAlreadyInStatus(error, status)) {
        this.logger.log(`User ${uuid} already ${status}; treating as success`);
        return this.getUserByUuid(uuid);
      }
      // Otherwise fall back to a direct status update via PATCH /api/users.
      return this.updateUser(uuid, { status });
    }
  }

  /** A030 = user already enabled, A029 = user already disabled. */
  private isAlreadyInStatus(error: unknown, status: 'ACTIVE' | 'DISABLED'): boolean {
    if (!(error instanceof RemnawaveApiError)) {
      return false;
    }
    return status === 'ACTIVE' ? error.errorCode === 'A030' : error.errorCode === 'A029';
  }

  private async request<T = unknown>(config: AxiosRequestConfig): Promise<T> {
    try {
      const response = await firstValueFrom(
        this.http.request<T>({
          ...config,
          baseURL: this.baseUrl,
          headers: {
            Authorization: `Bearer ${this.token}`,
            'Content-Type': 'application/json',
            ...config.headers,
          },
        }),
      );
      return response.data;
    } catch (error) {
      const axiosError = error as AxiosError;
      const status = axiosError.response?.status;
      const body = axiosError.response?.data;
      const responseData =
        body && typeof body === 'object' ? JSON.stringify(body) : body;
      const errorCode =
        body && typeof body === 'object'
          ? (body as AnyRecord)['errorCode']
          : undefined;
      this.logger.error(
        `Remnawave request failed: ${config.method} ${config.url} ${status ?? ''} ${responseData ?? ''}`,
      );
      throw new RemnawaveApiError(status, typeof errorCode === 'string' ? errorCode : undefined);
    }
  }

  private normalizeUser(payload: AnyRecord, fallbackUsername?: string): RemnawaveUser {
    const data = this.unwrap(payload);
    const uuid = this.pickString(data, ['uuid', 'id']);
    const shortUuid = this.pickString(data, ['shortUuid', 'shortId', 'subscriptionUuid']);
    if (!uuid) {
      throw new ServiceUnavailableException('Remnawave returned an invalid user payload');
    }

    const subscriptionPath =
      this.pickString(data, ['subscriptionUrl', 'subUrl', 'subscriptionUri']) ??
      (shortUuid ? `${this.subscriptionBaseUrl}/${shortUuid}` : `${this.subscriptionBaseUrl}/${uuid}`);

    return {
      uuid,
      shortUuid,
      username: this.pickString(data, ['username']) ?? fallbackUsername ?? uuid,
      status: this.pickString(data, ['status']),
      usedTrafficBytes: this.pickString(data, [
        'usedTrafficBytes',
        'usedTraffic',
        'trafficUsedBytes',
      ]) ?? '0',
      trafficLimitBytes: this.pickString(data, ['trafficLimitBytes', 'trafficLimit']),
      expiresAt: this.pickString(data, ['expiresAt', 'expireAt']),
      subscriptionUrl: subscriptionPath,
      lastConnectedNode: this.pickRecord(data, ['lastConnectedNode']),
    };
  }

  private unwrap(payload: AnyRecord): AnyRecord {
    const response = this.pickRecord(payload, ['response']);
    if (response) {
      return (
        this.pickRecord(response, ['user']) ??
        this.pickRecord(response, ['data']) ??
        response
      );
    }
    return this.pickRecord(payload, ['user']) ?? this.pickRecord(payload, ['data']) ?? payload;
  }

  private pickRecord(obj: AnyRecord, keys: string[]) {
    for (const key of keys) {
      const value = obj[key];
      if (value && typeof value === 'object' && !Array.isArray(value)) {
        return value as AnyRecord;
      }
    }
    return undefined;
  }

  private pickString(obj: AnyRecord, keys: string[]) {
    for (const key of keys) {
      const value = obj[key];
      if (typeof value === 'string') {
        return value;
      }
      if (typeof value === 'number' || typeof value === 'bigint') {
        return String(value);
      }
    }
    return undefined;
  }
}
