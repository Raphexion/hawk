# Access-token authentication for agents

This guide explains the intended experience for a person who wants an agent or
integration to use a Hawk JSON:API. You do not need to understand JWTs to use
the flow.

## The simple idea

There are two kinds of credentials:

```text
API token       long-term key; keep it private
      |
      | exchanged by trusted agent software
      v
JWT             short-term pass; used for API requests
```

The API token is like a house key. The JWT is like a visitor badge that works
for a short time. If somebody accidentally copies the visitor badge, it stops
working when it expires.

## What a teacher would do

1. Sign in to the Hawk website.
2. Open the API access or integrations page.
3. Click **Create API token**.
4. Give the token a name, such as `My planning assistant`, and choose the
   permissions it needs.
5. Copy the token when it is shown. It should only be shown once.
6. Store it in the trusted agent service's secret storage.

The API token should not be pasted into a chat, sent to the AI model, put in a
URL, or committed to source control. If it is exposed, revoke it and create a
new one.

## What the agent software does

The agent software uses the API token to ask Hawk for a short-lived JWT:

```http
POST /api/token
Content-Type: application/json

{"api_token":"the-long-term-token"}
```

Hawk checks the API token and returns something like:

```json
{
  "access_token": "eyJ...",
  "token_type": "Bearer",
  "expires_in": 900
}
```

The number `900` means that the JWT is valid for 900 seconds, or 15 minutes.
The agent then uses the JWT for normal API requests:

```http
GET /api/courses
Authorization: Bearer eyJ...
Accept: application/vnd.api+json
```

When the JWT expires, the agent asks for a new one. The teacher normally does
not need to do anything again. The long-term API token should never be sent to
the JSON:API endpoints themselves.

## What happens if a JWT leaks?

The copied JWT can be used by whoever has it until it expires. This is why JWTs
should be short-lived—typically 5 to 15 minutes—and should have only the
permissions needed by the agent.

If the long-term API token leaks, revoke it immediately. Revoking the API token
prevents the agent from obtaining more JWTs, although an already-issued JWT
remains valid until its expiry unless the host application also supports access
token revocation.

## Current Hawk integration

Hawk provides the verification side of this flow:

```elixir
plug Hawk.Token.BearerPlug,
  required: true,
  verifier: {Hawk.Token.JWT, :verify},
  verifier_opts: [
    key: MyApp.TokenKey.jwk(),
    issuer: "https://auth.example",
    audience: "my-hawk-api",
    roles: [:teacher, :agent]
  ]
```

`Hawk.Token.JWT` checks the signed JWT and turns it into a
`Hawk.Authority`. The host application still owns the API-token webpage,
API-token database, `/api/token` endpoint, JWT signing, rotation, and
revocation. Hawk does not currently create or store those long-term API
tokens.

Because token issuance is application-owned, the exact webpage and token
endpoint may differ between Hawk applications. The security requirements do
not change: use HTTPS, store long-term tokens as secrets, issue short-lived
JWTs, restrict permissions, and never place tokens in URLs or logs.
