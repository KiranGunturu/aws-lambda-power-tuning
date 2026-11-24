# How the API is secured

The API is protected in layers, from the edge inward. Each layer stops a different kind of problem, so one mistake doesn't expose the table.

| Layer | What it does | Where it's defined |
|---|---|---|
| 1. AWS WAF | Blocks known bad IPs, common exploits (SQLi, XSS, bad inputs) and any single IP sending more than `WafRateLimit` requests in 5 minutes | `WebAcl`, `WebAclAssociation` |
| 2. API key | Every call must send `x-api-key`. Calls without a valid key get **403** before Lambda runs | `PostMethod.ApiKeyRequired`, `ApiKey` |
| 3. Usage plan | Per-key throttling (rate and burst) and a monthly quota, so one client can't run up the bill | `UsagePlan`, `UsagePlanKey` |
| 4. Stage throttling | A ceiling for the whole method, even across many keys | `Stage.MethodSettings` |
| 5. Request validation | API Gateway checks the JSON body against a schema. Unknown operations or extra fields get **400** without invoking Lambda | `RequestModel`, `BodyValidator` |
| 6. Function-level checks | The code only ever uses the table in `TABLE_NAME`. A caller can't point it at another table | `src/lambda_function.py` |
| 7. Least-privilege IAM | The function role can call five DynamoDB actions on **one** table and write to **its own** log group. Nothing else | `FunctionRole` |
| 8. Invoke permission | Only this API's `POST /DynamoDBManager` can invoke the function | `InvokePermission` |
| 9. Encryption | DynamoDB and the results bucket are encrypted at rest. The bucket denies any non-TLS request, blocks all public access and disables ACLs | `Table`, `ResultsBucket`, `ResultsBucketPolicy` |
| 10. Logging and tracing | JSON access logs (with the API key ID and WAF status), error logs, metrics and X-Ray traces. Full request and response bodies are **not** logged | `Stage`, `AccessLogGroup` |

## Verify it

`scripts/test-api.sh` and the **Security checks** folder in the Postman collection run these checks:

| Request | Expected |
|---|---|
| Valid request with API key | 200 |
| No API key | 403 Forbidden |
| Unknown operation (`dropTable`) | 400 Bad Request |
| Another table name | 400 Bad Request |

## Things to know

- **API keys identify clients; they don't authenticate users.** They are fine for a demo, a partner integration or throttling per client. For end users, add an authorizer: Amazon Cognito user pools, a Lambda authorizer, or IAM (SigV4) for service-to-service calls.
- **WAF can block your own load test.** A single machine sending 35 requests per second exceeds the default 2,000 requests per 5 minutes. Deploy with `WAF_RATE_LIMIT=20000` (or temporarily set the rule to Count) while load testing, then put it back.
- **Rotate the API key** by creating a new key, attaching it to the usage plan, moving clients over, then deleting the old one.
- **Never commit the key.** The Postman environment template has an empty `apiKey` of type `secret`. `.gitignore` excludes `*.local.postman_environment.json`.
- **With a custom domain, disable the default endpoint** (`DisableDefaultEndpoint=true`), so clients can't bypass the domain and its TLS policy by calling `execute-api` directly.
