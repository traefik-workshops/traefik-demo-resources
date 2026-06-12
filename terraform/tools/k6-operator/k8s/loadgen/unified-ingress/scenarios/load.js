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

export const options = {
  vus: ${vus},
  duration: '${duration}',
  discardResponseBodies: true,
  insecureSkipTLSVerify: true,
};

// Unauthenticated edge routes — the bulk of the traffic. Lights up the per-compute
// (EKS/EC2/ECS/AKS) and per-route Traefik metrics behind the Traffic-by-Compute view.
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

// A couple of WAF attack payloads — denied at the edge (403). Feed the WAF/Loki
// story and the error-code panels without touching any backend.
const WAF_ATTACKS = [
  'https://waf.' + DOMAIN + '/?id=1%27%20OR%20%271%27%3D%271',
  'https://waf.' + DOMAIN + '/debug/pprof/heap',
];

// Benign AI prompts — REAL provider spend, off by default (the gateway's Redis
// token budget self-caps how much real spend a sustained run can incur).
const AI_OPENAI = 'https://ai.' + DOMAIN + '/v1/responses';
const AI_ANTHROPIC = 'https://ai.' + DOMAIN + '/v1/messages';

// setup() runs once: mint a JWT per user via the Keycloak password grant.
export function setup() {
  const tokens = {};
  USERS.forEach(function (u) {
    const body =
      'client_id=' + encodeURIComponent(CLIENT_ID) +
      '&client_secret=' + encodeURIComponent(CLIENT_SECRET) +
      '&grant_type=password&scope=openid' +
      '&username=' + encodeURIComponent(u.username) +
      '&password=' + encodeURIComponent(u.password);
    const res = http.post(KEYCLOAK_URL, body, {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    });
    if (res.status === 200) {
      try {
        const tok = JSON.parse(res.body).access_token;
        if (tok) { tokens[u.username] = tok; }
      } catch (e) { /* ignore */ }
    }
  });
  console.log('setup: minted ' + Object.keys(tokens).length + '/' + USERS.length + ' JWTs');
  return { usernames: Object.keys(tokens), tokens: tokens };
}

function publicGet() {
  http.get(randomItem(PUBLIC_GETS));
}

// Managed API: pick a random consumer; its group claim becomes app_id at the gate.
// Mostly reads (free tier 429s under load); an occasional write (free 403, premium 200).
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

function wafAttack() {
  http.get(randomItem(WAF_ATTACKS));
}

function aiCall() {
  if (Math.random() < 0.5) {
    http.post(
      AI_OPENAI,
      JSON.stringify({ model: 'gpt-4o-mini', input: 'Reply with exactly: gateway ok' }),
      { headers: { 'Content-Type': 'application/json' } }
    );
  } else {
    http.post(
      AI_ANTHROPIC,
      JSON.stringify({ model: 'claude-haiku-4-5', max_tokens: 16, messages: [{ role: 'user', content: 'Reply with exactly: gateway ok' }] }),
      { headers: { 'Content-Type': 'application/json' } }
    );
  }
}

// Weighted mix per iteration: 60% public edge, 25% managed API (per-consumer),
// 12% WAF attacks, 3% AI (only when enabled; otherwise falls back to public).
export default function (data) {
  const r = Math.random();
  if (r < 0.60) {
    publicGet();
  } else if (r < 0.85) {
    managedApi(data);
  } else if (r < 0.97) {
    wafAttack();
  } else if (AI_ENABLED) {
    aiCall();
  } else {
    publicGet();
  }
  sleep(Math.random() * 0.8 + 0.2);
}
