// Local stand-in for API-Football so the workflow's result logic can run without an API key or network. Not bundled into the CRE workflow.
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";

export const MOCK_API_KEY = "mock-api-football-key";

const fixture = (id: number, status: string, home: boolean | null, away: boolean | null) => ({
  fixture: { id, status: { short: status } },
  teams: { home: { winner: home }, away: { winner: away } },
});

/** Fixture id -> payload; the id doubles as the scenario. Expected outcome codes are listed in mock.test.ts. */
export const FIXTURES: Record<string, ReturnType<typeof fixture>> = {
  "1234": fixture(1234, "FT", null, null), // draw
  "2001": fixture(2001, "FT", true, false), // home win
  "2002": fixture(2002, "AET", false, true), // away win
  "2003": fixture(2003, "PST", null, null), // postponed -> cancelled
  "2004": fixture(2004, "NS", null, null), // not started: the workflow must not report
  "2005": fixture(2005, "PEN", false, true), // away win on penalties
};

export function startMockApiFootball(port = 0): Promise<{ server: Server; url: string }> {
  const server = createServer((req, res) => {
    const url = new URL(req.url ?? "/", "http://localhost");
    const send = (body: unknown) => {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify(body));
    };

    if (req.method !== "GET" || url.pathname !== "/fixtures") {
      res.writeHead(404).end();
      return;
    }
    // Like the real API, a bad key is HTTP 200 with a populated `errors` object.
    if (req.headers["x-apisports-key"] !== MOCK_API_KEY) {
      send({ errors: { token: "Error/Missing application key." }, response: [] });
      return;
    }
    const found = FIXTURES[url.searchParams.get("id") ?? ""];
    send({ errors: [], response: found ? [found] : [] });
  });

  return new Promise((resolve) => {
    server.listen(port, "127.0.0.1", () => {
      resolve({ server, url: `http://127.0.0.1:${(server.address() as AddressInfo).port}` });
    });
  });
}

if (import.meta.main) {
  const { url } = await startMockApiFootball(Number(process.env.MOCK_API_PORT ?? 8787));
  console.log(`Mock API-Football listening on ${url} (key: ${MOCK_API_KEY})`);
}
