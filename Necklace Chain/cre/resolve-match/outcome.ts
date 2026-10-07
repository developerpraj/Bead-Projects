// Pure result mapping for the CRE workflow: no SDK imports so it can be unit tested with plain Node.

/** Mirrors PoolTypes.Outcome in the contracts (NONE = 0 is never reported). */
export const OUTCOME = { HOME_WIN: 1, AWAY_WIN: 2, DRAW: 3, CANCELLED: 4 } as const;
export type OutcomeCode = (typeof OUTCOME)[keyof typeof OUTCOME];

const FINISHED = new Set(["FT", "AET", "PEN"]);
// AWD (technical loss) and WO (walkover) are not played results, so they refund like a cancellation.
const CANCELLED = new Set(["PST", "CANC", "ABD", "AWD", "WO"]);

type Side = { winner?: boolean | null };
type ApiFootballFixtures = {
  errors?: unknown;
  response?: Array<{
    fixture: { id: number | string; status: { short: string } };
    teams: { home: Side; away: Side };
  }>;
};

/**
 * Maps an API-Football `/fixtures?id=` payload to an outcome code. Throws while the fixture is unresolved,
 * so the workflow fails instead of reporting a result early.
 */
export function outcomeFromApiFootball(body: unknown, fixtureId: string): OutcomeCode {
  const data = body as ApiFootballFixtures | null;

  // API-Football answers bad keys and quota problems with HTTP 200 and a non-empty `errors` field.
  if (data && data.errors && typeof data.errors === "object" && Object.keys(data.errors).length > 0) {
    throw new Error(`API-Football error: ${JSON.stringify(data.errors)}`);
  }
  if (!data || !Array.isArray(data.response) || data.response.length === 0) {
    throw new Error(`No fixture data found for ID: ${fixtureId}`);
  }

  const fixture = data.response[0];
  if (String(fixture.fixture.id) !== String(fixtureId)) {
    throw new Error("Returned fixture id does not match the request");
  }

  const status = fixture.fixture.status.short;
  if (CANCELLED.has(status)) return OUTCOME.CANCELLED;
  if (!FINISHED.has(status)) throw new Error(`Match not resolved yet. Current status: ${status}`);

  // teams.*.winner is true / false for a decided side and null for a draw; it also covers penalty shootouts.
  const { home, away } = fixture.teams;
  if (home.winner === true) return OUTCOME.HOME_WIN;
  if (away.winner === true) return OUTCOME.AWAY_WIN;
  if (home.winner === null && away.winner === null) return OUTCOME.DRAW;
  throw new Error(`Cannot determine the winner for status ${status}`);
}

/** The fixture id comes from an onchain event; keep it to digits before it goes into a URL. */
export function assertFixtureId(fixtureId: string): string {
  if (!/^\d{1,12}$/.test(fixtureId)) throw new Error("fixtureId must be a numeric API-Football id");
  return fixtureId;
}
