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


## Acknowledgements

* The UAA team uses RubyMine, The Most Intelligent Ruby and Rails IDE
  
  [![RubyMine](https://raw.githubusercontent.com/fhanik/acknowledgment/master/icons/icon_RubyMine.png)](https://www.jetbrains.com/ruby/)
