# UAA release

See [docs](https://github.com/cloudfoundry/uaa-release/blob/develop/docs/uaa.md) taken from bosh-micro-cli circa mid-2015.

## Configuring required properties for UAA start-up

The properties below need to be generated explicitly per deployment of UAA release and are required for proper start-up and functioning of UAA. These are standard artifacts which can be generated using openssl. Please refer the topic below on how to generate a self signed cert.

#### SAML Service Provider Configuration

```
login.saml.serviceProviderCertificate:
description: "UAA SAML Service provider certificate. This is used for signing outgoing SAML Authentication Requests"

login.saml.serviceProviderKey:
description: "Private key for the service provider certificate."
```

#### JWT Signing Keys(verification key needn't be set as we derive it from the private key)

```
uaa.jwt.policy.keys:
 description: "Map of key IDs and signing keys, each defined with a property `signingKey`"
    example:
      key-1:
        signingKey
 
 uaa.jwt.policy.active_key_id:
 description: "The ID of the JWT signing key to be used when signing tokens."
 example: "key-1" 
```

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

## Contributing to uaa-release

### General workflow

1. [Fork](https://help.github.com/articles/fork-a-repo) the repository and make a local [clone](https://help.github.com/articles/fork-a-repo#step-2-create-a-local-clone-of-your-fork)
2. Create a feature branch from the development branch

   ```bash
   cd uaa-release
   git checkout develop
   git submodule update
   git checkout -b my_branch
   ```
3. Make changes on your branch
4. Run the tests (requires ruby) `bundle install && bundle exec rake`
5. Deploy your version of uaa-release to test the changes
6. Push to your fork (`git push origin my_branch`) and
   [submit a pull request](https://help.github.com/articles/creating-a-pull-request)
   selecting `develop` as the target branch

## Java Runtime Environments

   Java Runtime Environments are graciously supplied by the Cloud Foundry Java Buildpack Team

   JDK - https://java-buildpack.cloudfoundry.org/openjdk-jdk/trusty/x86_64/index.yml
   JRE - https://java-buildpack.cloudfoundry.org/openjdk/trusty/x86_64/index.yml

## Acknowledgements

* We'd like to extend a thank you to all our users, contributors and supporters!
