import { jsonSafe } from '../src/common/serializers/json-safe';

describe('jsonSafe', () => {
  it('converts nested bigint values to strings', () => {
    expect(
      jsonSafe({
        id: 'vpn-1',
        trafficLimitBytes: 107374182400n,
        nested: {
          usedTrafficBytes: 1n,
        },
      }),
    ).toEqual({
      id: 'vpn-1',
      trafficLimitBytes: '107374182400',
      nested: {
        usedTrafficBytes: '1',
      },
    });
  });
});
