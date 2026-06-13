import http from 'k6/http';
import { sleep } from 'k6';
import { randomItem } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

// --- Config (rendered from Terraform) ----------------------------------------
const DOMAIN = '${domain}';
const KEYCLOAK_URL = '${keycloak_url}';
const CLIENT_ID = '${client_id}';
const CLIENT_SECRET = '${client_secret}';
const USERS = JSON.parse('${users_json}');
const AI_ENABLED = ${ai_enabled};
const OPENAI_MODELS = JSON.parse('${openai_models}');
const ANTHROPIC_MODELS = JSON.parse('${anthropic_models}');
const AI_MAX_TOKENS = ${ai_max_tokens};

// Two scenarios: high-volume edge traffic (free) + a deliberately LOW-rate AI scenario
// (constant arrival, ai_rpm/min) so real provider spend stays tiny. The dashboards inflate
// the displayed AI token/spend numbers separately.
const scenarios = {
  edge: { executor: 'constant-vus', vus: ${vus}, duration: '${duration}', exec: 'edge' },
};
if (AI_ENABLED) {
  scenarios.ai = {
    executor: 'constant-arrival-rate',
    rate: ${ai_rpm},
    timeUnit: '1m',
    duration: '${duration}',
    preAllocatedVUs: 5,
    maxVUs: 10,
    exec: 'ai',
  };
}

export const options = {
  discardResponseBodies: true,
  insecureSkipTLSVerify: true,
  // 40 sequential token mints against a possibly-cold Keycloak (e.g. right after a reseed)
  // can take a while; give setup() generous headroom so it never times out at the default 60s.
  setupTimeout: '300s',
  scenarios: scenarios,
};

// Unauthenticated edge routes — the bulk of the traffic. Lights up the per-compute and
// per-route Traefik metrics behind the Traffic-by-Compute view.
const PUBLIC_GETS = [
  'https://lb.' + DOMAIN + '/',
  'https://lbsticky.' + DOMAIN + '/',
  'https://ec2-whoami.' + DOMAIN + '/',
  'https://ecs-whoami.' + DOMAIN + '/',
  'https://aks-whoami.' + DOMAIN + '/',
  'https://orders.' + DOMAIN + '/orders',
  'https://mirror.' + DOMAIN + '/',
  'https://lbmirror.' + DOMAIN + '/',
  'https://canary-compute.' + DOMAIN + '/',
  'https://hrw.' + DOMAIN + '/',
  'https://leasttime.' + DOMAIN + '/',
  'https://waf.' + DOMAIN + '/',
];

// WAF attack payloads — denied at the edge (403). Feed the WAF/Loki story + error panels.
const WAF_ATTACKS = [
  'https://waf.' + DOMAIN + '/?id=1%27%20OR%20%271%27%3D%271',
  'https://waf.' + DOMAIN + '/debug/pprof/heap',
];

const AI_OPENAI = 'https://ai.' + DOMAIN + '/v1/responses';
const AI_ANTHROPIC = 'https://ai.' + DOMAIN + '/v1/messages';

// setup() runs once: mint a JWT per user via the Keycloak password grant (for the managed API).
// Retries per user so a transient Keycloak blip at test start (e.g. right after a reseed) can't
// zero out the whole run.
export function setup() {
  const tokens = {};
  USERS.forEach(function (u) {
    const body =
      'client_id=' + encodeURIComponent(CLIENT_ID) +
      '&client_secret=' + encodeURIComponent(CLIENT_SECRET) +
      '&grant_type=password&scope=openid' +
      '&username=' + encodeURIComponent(u.username) +
      '&password=' + encodeURIComponent(u.password);
    for (let attempt = 0; attempt < 3; attempt++) {
      // responseType 'text' overrides the global discardResponseBodies — setup() needs the
      // body to read access_token.
      const res = http.post(KEYCLOAK_URL, body, {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        responseType: 'text',
      });
      if (res.status === 200) {
        try {
          const tok = JSON.parse(res.body).access_token;
          if (tok) { tokens[u.username] = tok; break; }
        } catch (e) { /* retry */ }
      }
      sleep(1);
    }
  });
  console.log('setup: minted ' + Object.keys(tokens).length + '/' + USERS.length + ' JWTs');
  return { usernames: Object.keys(tokens), tokens: tokens };
}

// --- edge scenario: public routes + managed API + WAF attacks ----------------
export function edge(data) {
  const r = Math.random();
  if (r < 0.65) {
    http.get(randomItem(PUBLIC_GETS));
  } else if (r < 0.90) {
    managedApi(data);
  } else {
    http.get(randomItem(WAF_ATTACKS));
  }
  sleep(Math.random() * 0.8 + 0.2);
}

// Managed API: random consumer; its group claim becomes app_id at the gate. Mostly reads
// (free tier 429s under load); an occasional write (free 403, premium 200).
function managedApi(data) {
  if (!data.usernames.length) { return; }
  const user = randomItem(data.usernames);
  const auth = 'Bearer ' + data.tokens[user];
  if (Math.random() < 0.8) {
    http.get('https://whoami.' + DOMAIN + '/', { headers: { Authorization: auth } });
  } else {
    http.post(
      'https://whoami.' + DOMAIN + '/api',
      JSON.stringify({ message: 'load from ' + user, count: 1 }),
      { headers: { Authorization: auth, 'Content-Type': 'application/json' } }
    );
  }
}

// --- ai scenario: low-rate, rotates 5 OpenAI + 5 Anthropic models ------------
export function ai() {
  if (Math.random() < 0.5) {
    http.post(
      AI_OPENAI,
      JSON.stringify({ model: randomItem(OPENAI_MODELS), input: 'Reply with exactly: gateway ok', max_output_tokens: AI_MAX_TOKENS }),
      { headers: { 'Content-Type': 'application/json' } }
    );
  } else {
    http.post(
      AI_ANTHROPIC,
      JSON.stringify({ model: randomItem(ANTHROPIC_MODELS), max_tokens: AI_MAX_TOKENS, messages: [{ role: 'user', content: 'Reply with exactly: gateway ok' }] }),
      { headers: { 'Content-Type': 'application/json', 'anthropic-version': '2023-06-01' } }
    );
  }
}
