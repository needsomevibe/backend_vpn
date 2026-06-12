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

@Injectable()
export class RemnawaveService {
  private readonly logger = new Logger(RemnawaveService.name);
  private readonly baseUrl: string;
  private readonly token: string;
  private readonly subscriptionBaseUrl: string;

  constructor(
    private readonly http: HttpService,
    config: ConfigService,
  ) {
    this.baseUrl = config.getOrThrow<string>('REMNAWAVE_BASE_URL').replace(/\/$/, '');
    this.token = config.getOrThrow<string>('REMNAWAVE_API_TOKEN');
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
        trafficLimitBytes: input.trafficLimitBytes,
        trafficLimitStrategy: 'NO_RESET',
        expireAt: input.expiresAt.toISOString(),
        expiresAt: input.expiresAt.toISOString(),
        activeInternalSquads: ['default'],
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
    const response = await this.request<AnyRecord>({
      method: 'PATCH',
      url: `/api/users/${uuid}`,
      data: {
        ...input,
        expireAt: input.expiresAt?.toISOString(),
        expiresAt: input.expiresAt?.toISOString(),
      },
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
    try {
      const response = await this.request<AnyRecord>({
        method: 'GET',
        url: `/api/bandwidth-stats/users/${uuid}`,
      });
      const data = this.unwrap(response);
      return {
        usedTrafficBytes: this.pickString(data, ['usedTrafficBytes', 'totalBytes', 'bytes']) ?? '0',
        nodeLocation: this.pickNodeLocation(data),
      };
    } catch {
      const user = await this.getUserByUuid(uuid);
      return {
        usedTrafficBytes: user.usedTrafficBytes,
        nodeLocation: user.lastConnectedNode?.country ?? user.lastConnectedNode?.name,
      };
    }
  }

  private async updateStatus(uuid: string, status: string, actionUrl: string) {
    try {
      const response = await this.request<AnyRecord>({ method: 'POST', url: actionUrl });
      return this.normalizeUser(response);
    } catch {
      return this.updateUser(uuid, { status });
    }
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
      this.logger.error(
        `Remnawave request failed: ${config.method} ${config.url} ${axiosError.response?.status ?? ''}`,
      );
      throw new ServiceUnavailableException('Remnawave API is unavailable');
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

  private pickNodeLocation(data: AnyRecord) {
    const node = this.pickRecord(data, ['lastConnectedNode', 'node']);
    if (!node) {
      return undefined;
    }
    return this.pickString(node, ['country', 'name', 'location']);
  }
}
