# Adding a custom domain to API Gateway

By default the API is reachable at a generated URL:

```
https://<api-id>.execute-api.us-west-2.amazonaws.com/prod/DynamoDBManager
```

With a custom domain, clients call a stable, readable URL instead, and you can change the API behind it without changing clients:

```
https://api.example.com/DynamoDBManager
```

## What the template creates

When you pass both `CustomDomainName` and `HostedZoneId`, the stack adds four resources:

| Resource | Purpose |
|---|---|
| `Certificate` (ACM) | A public TLS certificate for the domain. CloudFormation adds the DNS validation record to your hosted zone and waits until the certificate is issued. |
| `ApiDomainName` | A **regional** API Gateway custom domain using that certificate, with the `TLS_1_2` security policy. |
| `ApiBasePathMapping` | Maps the domain root to the `prod` stage, so `/DynamoDBManager` works without the stage name. |
| `ApiDnsRecord` (Route 53) | An alias `A` record pointing the domain at the API Gateway regional endpoint. |

For a regional endpoint, the certificate must be in the **same Region as the API**. (Edge-optimized endpoints need the certificate in us-east-1.)

## Deploy it

Prerequisite: a public Route 53 hosted zone for the parent domain, for example `example.com`.

```bash
DOMAIN=api.example.com ZONE_ID=Z0123456789ABCDEFGHIJ ./scripts/deploy.sh
```

The first deploy can take a few minutes while ACM validates the certificate. Then:

```bash
curl -s -X POST "https://api.example.com/DynamoDBManager" \
  -H "Content-Type: application/json" -H "x-api-key: $API_KEY" \
  -d '{"operation":"ping","payload":{}}'
```

In Postman, change `baseUrl` to `https://api.example.com` (no stage in the path).

## Lock down the default endpoint

Once clients use the custom domain, turn off the generated `execute-api` URL so nobody can bypass the domain:

```bash
aws cloudformation deploy ... --parameter-overrides DisableDefaultEndpoint=true
```

## Domain not in Route 53?

Remove `HostedZoneId`, create the certificate and custom domain in the console, then add a `CNAME` at your DNS provider pointing to the API Gateway domain name target shown on the **Custom domain names** page.
