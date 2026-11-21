export const ROUTES = {
  home: "/",
  createTrail: "/trails/new",
  trailDetail: "/trails/:id",
} as const;

export type AppRoute =
  | (typeof ROUTES)[keyof typeof ROUTES]
  | `/trails/${string}`;

export const trailDetailPath = (id: string): AppRoute => `/trails/${id}`;
