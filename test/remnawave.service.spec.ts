import { HttpService } from '@nestjs/axios';
import { ConfigService } from '@nestjs/config';
import { Test } from '@nestjs/testing';
import { of } from 'rxjs';
import { RemnawaveService } from '../src/remnawave/remnawave.service';

describe('RemnawaveService', () => {
  const http = {
    request: jest.fn(),
  };

  async function buildService() {
    const moduleRef = await Test.createTestingModule({
      providers: [
        RemnawaveService,
        { provide: HttpService, useValue: http },
        { provide: ConfigService, useValue: { getOrThrow: jest.fn() } },
      ],
    })
      .overrideProvider(ConfigService)
      .useValue({
        getOrThrow: (key: string) => {
          const values: Record<string, string> = {
            REMNAWAVE_BASE_URL: 'https://panel.yeats.uz',
            REMNAWAVE_API_TOKEN: 'secret-token',
            SUBSCRIPTION_BASE_URL: 'https://sub.yeats.uz',
          };
          return values[key];
        },
      })
      .compile();
    return moduleRef.get(RemnawaveService);
  }

  beforeEach(() => jest.clearAllMocks());

  it('creates users with backend-only authorization and normalizes response payloads', async () => {
    http.request.mockReturnValue(
      of({
        data: {
          response: {
            user: {
              uuid: 'uuid-1',
              shortUuid: 'abc123',
              username: 'ios_user',
              usedTrafficBytes: '0',
            },
          },
        },
      }),
    );

    const service = await buildService();
    const result = await service.createUser({
      username: 'ios_user',
      trafficLimitBytes: '107374182400',
      expiresAt: new Date('2026-07-12T00:00:00.000Z'),
    });

    expect(http.request).toHaveBeenCalledWith(
      expect.objectContaining({
        baseURL: 'https://panel.yeats.uz',
        url: '/api/users',
        headers: expect.objectContaining({
          Authorization: 'Bearer secret-token',
        }),
      }),
    );
    expect(result).toEqual(
      expect.objectContaining({
        uuid: 'uuid-1',
        shortUuid: 'abc123',
        subscriptionUrl: 'https://sub.yeats.uz/abc123',
      }),
    );
  });

  it('normalizes nested Remnawave user traffic counters', async () => {
    http.request.mockReturnValue(
      of({
        data: {
          response: {
            user: {
              uuid: 'uuid-traffic',
              shortUuid: 'traffic',
              username: 'ios_user',
              userTraffic: {
                uploadBytes: '1073741824',
                downloadBytes: '2147483648',
                trafficLimitBytes: '107374182400',
              },
            },
          },
        },
      }),
    );

    const service = await buildService();
    const result = await service.getUserUsage('uuid-traffic');

    expect(result).toEqual(
      expect.objectContaining({
        usedTrafficBytes: '3221225472',
        trafficLimitBytes: '107374182400',
      }),
    );
  });
});
