# UAA release

See [docs](https://github.com/cloudfoundry/bosh-micro-cli/blob/master/docs/uaa.md) in bosh-micro-cli.

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

## Notes

- The property `uaa.port` can't be set to `8989` because this port is used by BOSH to monitor the server.

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
4. Deploy your version of uaa-release to test the changes
5. Push to your fork (`git push origin my_branch`) and
   [submit a pull request](https://help.github.com/articles/creating-a-pull-request)
   selecting `develop` as the target branch

## Deploying to a bosh-lite environment

   We have provided [a sample manifest](docs/bosh-lite-uaa-release.yml)
   for a bosh-lite uaa-release deployment. 
   Make sure you modify the director uuid in the manifest to match yours 

       bosh target 192.168.50.4
       bosh login admin admin
       bosh upload stemcell https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent --skip-if-exists
       bosh deployment docs/bosh-lite-uaa-release.yml
       bosh deploy
    
   After that you can get the IP address and add the hostname to your `/etc/hosts` file
  
   You may want to setup an entry in your `/etc/hosts`
      
      10.244.0.118    uaa-minimal.bosh-lite.com
   


## Acknowledgements

* The UAA team uses RubyMine, The Most Intelligent Ruby and Rails IDE
  
  [![RubyMine](https://raw.githubusercontent.com/fhanik/acknowledgment/master/icons/icon_RubyMine.png)](https://www.jetbrains.com/ruby/)
