# Ad-hoc API access

How to call any PBS API endpoint with the `pbs_api_request` Bolt task. Its parameters are
documented in [REFERENCE.md](../REFERENCE.md#pbs_api_request).

The task calls any PBS REST API endpoint directly, without writing Puppet code: useful for one-off
operations and for endpoints that no resource type covers. Endpoint paths and parameter names
follow the official [PBS API viewer](https://pbs.proxmox.com/docs/api-viewer/index.html).

## Passing the token secret safely

Do not pass `token_secret` on the command line: it lands in shell history and is visible in
process listings (`ps`) while the task runs. Use an inventory secret backend, or a mode-`0600`
parameters file for a local one-off request:

```sh
umask 077
request_file=$(mktemp)
trap 'rm -f "$request_file"' EXIT

read -rsp 'PBS token secret: ' TOKEN_SECRET
printf '\n'
export TOKEN_SECRET

ruby -rjson -e '
  puts JSON.generate(
    host: "localhost",
    token_id: "puppet@pbs!puppet-token",
    token_secret: ENV.fetch("TOKEN_SECRET"),
    method: "GET",
    path: "/version",
  )
' > "$request_file"
unset TOKEN_SECRET

bolt task run proxmox_backup_server::pbs_api_request \
  --targets pbs.example.com \
  --params "@${request_file}"

rm -f "$request_file"
trap - EXIT
```

The temporary file is removed after the request; the shell trap also removes it if the command is
interrupted.

## TLS

The task verifies TLS certificates by default. Pass `ssl_ca_file` for a private CA, or
`ssl_verify: false` only for a request against `localhost`. A fresh PBS installation serves a
self-signed certificate that fails verification; see [Class parameters and TLS](class-parameters.md#tls-verification)
for the same trade-off in the transport.
