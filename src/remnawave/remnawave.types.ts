export type RemnawaveUser = {
  uuid: string;
  shortUuid?: string;
  username: string;
  status?: string;
  usedTrafficBytes: string;
  trafficLimitBytes?: string;
  expiresAt?: string;
  subscriptionUrl: string;
  lastConnectedNode?: {
    name?: string;
    country?: string;
  } | null;
};

export type CreateRemnawaveUserInput = {
  username: string;
  trafficLimitBytes: string;
  expiresAt: Date;
};

export type UpdateRemnawaveUserInput = Partial<{
  username: string;
  trafficLimitBytes: string;
  expiresAt: Date;
  status: string;
}>;

export type RemnawaveUsage = {
  usedTrafficBytes: string;
  nodeLocation?: string;
};
