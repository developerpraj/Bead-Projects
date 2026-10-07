import { test } from "node:test";
import assert from "node:assert/strict";
import { MOCK_API_KEY, startMockApiFootball } from "./api-football-server.ts";
import { OUTCOME, outcomeFromApiFootball } from "../outcome.ts";

const { server, url } = await startMockApiFootball(0);
test.after(() => server.close());

const fetchFixture = async (id: string, key = MOCK_API_KEY) =>
  (await fetch(`${url}/fixtures?id=${id}`, { headers: { "x-apisports-key": key } })).json();

test("mock scenarios map to the expected outcome codes", async () => {
  const expected: Record<string, number> = {
    "1234": OUTCOME.DRAW,
    "2001": OUTCOME.HOME_WIN,
    "2002": OUTCOME.AWAY_WIN,
    "2003": OUTCOME.CANCELLED,
    "2005": OUTCOME.AWAY_WIN,
  };
  for (const [id, code] of Object.entries(expected)) {
    assert.equal(outcomeFromApiFootball(await fetchFixture(id), id), code, id);
  }
});

test("a fixture that has not started is not reported", async () => {
  const body = await fetchFixture("2004");
  assert.throws(() => outcomeFromApiFootball(body, "2004"), /not resolved yet/);
});

test("bad key and unknown fixture behave like the real API", async () => {
  const badKey = await fetchFixture("1234", "wrong");
  assert.throws(() => outcomeFromApiFootball(badKey, "1234"), /API-Football error/);
  const unknown = await fetchFixture("9999");
  assert.throws(() => outcomeFromApiFootball(unknown, "9999"), /No fixture data/);
});
