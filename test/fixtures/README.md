# Local TLS fixtures

`server-key.pem` is a **public, test-only private key**, intentionally committed
for the offline localhost TLS server. Never use it for a real server.
`server-cert.pem` is signed by `ca.pem`; its only DNS name is `localhost`, allowing
tests to prove that a trusted certificate still fails for `127.0.0.1`.
Certificates expire in September 2036. The CA private key is not retained.

To replace the fixtures, run these commands in a temporary directory and copy
only the three named fixture files back here:

```sh
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout ca-key.pem -out ca.pem -subj '/CN=TypeSafe Test CA' \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign'
openssl req -newkey rsa:2048 -nodes -keyout server-key.pem \
  -out server.csr -subj '/CN=localhost'
cat > extensions.cnf <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost
EOF
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out server-cert.pem -days 3650 -extfile extensions.cnf
```

Discard the temporary directory after copying the fixtures.
