# UAA release

See [docs](https://github.com/cloudfoundry/bosh-micro-cli/blob/master/docs/uaa.md) in bosh-micro-cli.

## Configuring UAA to run on https with SSL

By default UAA is configured to use SSL with a self-signed certificate and will be started on port 8443.

## Using your own certificate

Add the following properties to your manifest:

- `uaa.sslCertificate`: Specifies your SSL certificate

- `uaa.sslPrivateKey`: Specifies your private key.  The key must be a passphrase-less key.

## Generating a self-signed certificate

1. Generate your private key with any passphrase

`openssl genrsa -aes256 -out server.key 1024`

2. Remove passphrase from key

`openssl rsa -in server.key -out server.key`

3. Generate certificate signing request for CA

`openssl req -x509 -sha256 -new -key server.key -out server.csr`

4. Generate self-signed certificate with 365 days expiry-time

`openssl x509 -sha256 -days 365 -in server.csr -signkey server.key -out selfsigned.crt`

## Notes

- The property `uaa.port` can't be set to `8989` because this port is used by BOSH to monitor the server.
