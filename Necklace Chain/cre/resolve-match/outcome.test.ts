// Offline checks for outcome.ts. Run with: npm test
import { test } from "node:test";
import assert from "node:assert/strict";
import { OUTCOME, assertFixtureId, outcomeFromApiFootball } from "./outcome.ts";

const fixture = (status: string, home: boolean | null, away: boolean | null, id: number | string = 1234) => ({
  errors: [],
  response: [{ fixture: { id, status: { short: status } }, teams: { home: { winner: home }, away: { winner: away } } }],
});

test("home win after full time", () => {
  assert.equal(outcomeFromApiFootball(fixture("FT", true, false), "1234"), OUTCOME.HOME_WIN);
});

test("away win", () => {
  assert.equal(outcomeFromApiFootball(fixture("FT", false, true), "1234"), OUTCOME.AWAY_WIN);
});

test("draw when both winner flags are null", () => {
  assert.equal(outcomeFromApiFootball(fixture("FT", null, null), "1234"), OUTCOME.DRAW);
});

test("extra time and penalty shootouts use the winner flag", () => {
  assert.equal(outcomeFromApiFootball(fixture("AET", true, false), "1234"), OUTCOME.HOME_WIN);
  assert.equal(outcomeFromApiFootball(fixture("PEN", false, true), "1234"), OUTCOME.AWAY_WIN);
});

test("cancelled, postponed, abandoned and awarded fixtures refund", () => {
  for (const s of ["PST", "CANC", "ABD", "AWD", "WO"]) {
    assert.equal(outcomeFromApiFootball(fixture(s, null, null), "1234"), OUTCOME.CANCELLED, s);
  }
});

test("unresolved fixtures throw instead of reporting", () => {
  for (const s of ["TBD", "NS", "1H", "HT", "2H", "ET", "BT", "P", "SUSP", "INT", "LIVE"]) {
    assert.throws(() => outcomeFromApiFootball(fixture(s, null, null), "1234"), /not resolved yet/, s);
  }
});

test("API errors returned with HTTP 200 throw", () => {
  assert.throws(
    () => outcomeFromApiFootball({ errors: { token: "Error/Missing application key" }, response: [] }, "1234"),
    /API-Football error/,
  );
});

test("empty or malformed responses throw", () => {
  assert.throws(() => outcomeFromApiFootball({ errors: [], response: [] }, "1234"), /No fixture data/);
  assert.throws(() => outcomeFromApiFootball(null, "1234"), /No fixture data/);
  assert.throws(() => outcomeFromApiFootball("nope", "1234"), /No fixture data/);
});

test("a response for a different fixture id is rejected", () => {
  assert.throws(() => outcomeFromApiFootball(fixture("FT", true, false, 9999), "1234"), /does not match/);
});

test("a finished match with no determinable winner throws", () => {
  assert.throws(() => outcomeFromApiFootball(fixture("PEN", false, false), "1234"), /Cannot determine the winner/);
});

test("fixture ids must be numeric", () => {
  assert.equal(assertFixtureId("1234"), "1234");
  for (const bad of ["", "12a", "1234&x=1", "../etc", "1".repeat(13)]) {
    assert.throws(() => assertFixtureId(bad), /numeric/, bad);
  }
});
