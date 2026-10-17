# YubiKey PIV login and Login keychain unlock on macOS

This guide configures a YubiKey PIV token for macOS account authentication
through OpenSCToken.  PIV slot 9A authenticates the account and slot 9D wraps
the Login keychain unlock secret.

This is smart-card authentication, not Touch ID.  macOS still presents its
smart-card credential field and requires a submit action before it asks the
YubiKey to perform a private-key operation.  A PIV touch authorizes a pending
operation; it is not an unsolicited input event that can wake or submit the
macOS login window.

## Security and recovery first

- Keep a tested administrator account password available.  Do not enable
  mandatory smart-card enforcement while testing.
- Generating a key permanently replaces the private key already in that PIV
  slot.  Export any existing public certificates first.  A private key
  generated on a YubiKey cannot be backed up or recovered.
- `--pin-policy never` intentionally removes the PIN factor from that key.
  Security then depends on possession of the YubiKey and its physical-touch
  policy.  Use a PIN-protected policy instead if two-factor smart-card login
  is required.
- Never put a PIV PIN or management key directly in a shared script, shell
  history, issue, or pull request.  Let `ykman` prompt for secrets.
- Slot 9E is the Card Authentication slot and is not a substitute for the 9A
  login identity or 9D key-management identity expected by macOS.
- CryptoTokenKit is not available in the FileVault preboot environment.  A
  normal password or another FileVault-supported method may still be required
  for the first unlock after startup.

The PIN-policy metadata used by this implementation requires YubiKey PIV
firmware 5.3 or later.  YubiKey firmware cannot be upgraded in the field; use
a sufficiently recent key.

## 1. Install the required tools

Install full Xcode and select it as the active developer directory:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

Install the build and provisioning tools:

```sh
brew install autoconf automake libtool pkg-config help2man gengetopt ykman opensc
```

Confirm that exactly the intended YubiKey is connected and inspect its PIV
state:

```sh
ykman list --serials
ykman info
ykman piv info
ykman piv keys info 9a
ykman piv keys info 9d
```

If slots 9A and 9D already have the required keys, certificates, and policies,
skip to [Build OpenSCToken](#3-build-opensctoken).

## 2. Provision PIV slots 9A and 9D

The example below creates RSA-2048 keys with these policies:

| Slot | Purpose | PIN policy | Touch policy |
| --- | --- | --- | --- |
| 9A | macOS account authentication | `never` | `always` |
| 9D | Login keychain wrapping | `never` | `cached` |

`cached` normally caches a successful touch for about 15 seconds.  Use
`always` for 9D if every keychain unwrap must require a separate touch.

Create a private working directory:

```sh
umask 077
PIV_WORKDIR="$(mktemp -d /private/tmp/opensctoken-piv.XXXXXX)"
echo "$PIV_WORKDIR"
```

If the slots are already populated, export the existing public certificates
before replacing their keys:

```sh
ykman piv certificates export 9a "$PIV_WORKDIR/old-9a.pem" || true
ykman piv certificates export 9d "$PIV_WORKDIR/old-9d.pem" || true
```

Generate the two private keys on the YubiKey.  These commands are destructive
to the existing keys in those slots:

```sh
ykman piv keys generate \
  --algorithm RSA2048 \
  --pin-policy never \
  --touch-policy always \
  9a "$PIV_WORKDIR/9a-public.pem"

ykman piv keys generate \
  --algorithm RSA2048 \
  --pin-policy never \
  --touch-policy cached \
  9d "$PIV_WORKDIR/9d-public.pem"
```

### Issue suitable certificates

Use certificates issued by the organization's CA when available.  For an
isolated test, the following commands create a local test CA and issue two
leaf certificates.  Keep `test-ca-key.pem` secure if the certificates will be
renewed later.

```sh
openssl req -x509 -newkey rsa:3072 -sha256 -nodes \
  -days 3650 \
  -subj "/CN=OpenSCToken local test CA" \
  -keyout "$PIV_WORKDIR/test-ca-key.pem" \
  -out "$PIV_WORKDIR/test-ca.pem"

ykman piv certificates request \
  --subject "CN=macOS PIV Authentication" \
  9a "$PIV_WORKDIR/9a-public.pem" "$PIV_WORKDIR/9a.csr.pem"

ykman piv certificates request \
  --subject "CN=macOS PIV Key Management" \
  9d "$PIV_WORKDIR/9d-public.pem" "$PIV_WORKDIR/9d.csr.pem"
```

Create certificate-extension files:

```sh
cat >"$PIV_WORKDIR/9a.ext" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=clientAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

cat >"$PIV_WORKDIR/9d.ext" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,keyEncipherment,dataEncipherment
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF
```

Sign the certificates.  The explicit 9D `keyEncipherment` usage is important:
macOS uses that key to protect the Login keychain unlock secret.

```sh
openssl x509 -req -sha256 -days 3650 \
  -in "$PIV_WORKDIR/9a.csr.pem" \
  -CA "$PIV_WORKDIR/test-ca.pem" \
  -CAkey "$PIV_WORKDIR/test-ca-key.pem" \
  -CAcreateserial \
  -extfile "$PIV_WORKDIR/9a.ext" \
  -out "$PIV_WORKDIR/9a-cert.pem"

openssl x509 -req -sha256 -days 3650 \
  -in "$PIV_WORKDIR/9d.csr.pem" \
  -CA "$PIV_WORKDIR/test-ca.pem" \
  -CAkey "$PIV_WORKDIR/test-ca-key.pem" \
  -CAserial "$PIV_WORKDIR/test-ca.srl" \
  -extfile "$PIV_WORKDIR/9d.ext" \
  -out "$PIV_WORKDIR/9d-cert.pem"
```

Import the matching public certificates.  Allow `ykman` to prompt for any
required PIV authorization instead of adding a PIN to the command line:

```sh
ykman piv certificates import --verify --no-update-chuid \
  9a "$PIV_WORKDIR/9a-cert.pem"

ykman piv certificates import --verify --no-update-chuid \
  9d "$PIV_WORKDIR/9d-cert.pem"
```

Verify the result:

```sh
ykman piv keys info 9a
ykman piv keys info 9d
ykman piv certificates export 9a - | openssl x509 -noout -subject -issuer -text
ykman piv certificates export 9d - | openssl x509 -noout -subject -issuer -text
```

Confirm that 9D reports `Key Encipherment` under `X509v3 Key Usage`.

## 3. Build OpenSCToken

Clone the repository and build its OpenSSL, OpenPACE, and OpenSC dependencies:

```sh
git clone https://github.com/frankmorgner/OpenSCToken.git
cd OpenSCToken
./bootstrap
```

Build and stage the app:

```sh
xcodebuild \
  -target OpenSCTokenApp \
  -configuration Release \
  -project OpenSCTokenApp.xcodeproj \
  install \
  DSTROOT="${PWD}/build"
```

The build requires valid app and extension signing.  Select a development
team in Xcode or supply the appropriate signing settings for the local
environment.  Verify the result before installation:

```sh
codesign --verify --deep --strict --verbose=2 \
  build/Applications/Utilities/OpenSCTokenApp.app
```

## 4. Install and register the CryptoTokenKit extension

Keep a copy of any previously installed OpenSCTokenApp before replacing it.
Install the newly built app:

```sh
sudo ditto \
  build/Applications/Utilities/OpenSCTokenApp.app \
  /Applications/Utilities/OpenSCTokenApp.app
```

Register the extension for the current user and the login SecurityAgent:

```sh
pluginkit -a \
  /Applications/Utilities/OpenSCTokenApp.app/Contents/PlugIns/OpenSCToken.appex

sudo -u _securityagent pluginkit -a \
  /Applications/Utilities/OpenSCTokenApp.app/Contents/PlugIns/OpenSCToken.appex

sudo sc_auth enable_for_login \
  -c org.opensc-project.mac.opensctoken.OpenSCTokenApp.OpenSCToken
```

Verify registration:

```sh
pluginkit -v -m -D \
  -i org.opensc-project.mac.opensctoken.OpenSCTokenApp.OpenSCToken
```

Only one PIV token driver should claim the card.  Read the current setting
before changing it:

```sh
sudo defaults read \
  /Library/Preferences/com.apple.security.smartcard DisabledTokens
```

If no other disabled-token entries need to be preserved, disable Apple's PIV
driver so OpenSCToken handles the YubiKey:

```sh
sudo defaults write \
  /Library/Preferences/com.apple.security.smartcard DisabledTokens \
  -array com.apple.CryptoTokenKit.pivtoken
```

If the array already contains entries, preserve them when adding the Apple
PIV bundle identifier instead of overwriting the array.

## 5. Refresh CryptoTokenKit completely

`ctkd`, `ctkbind`, and the CryptoTokenKit Authentication Hints Provider cache
token capabilities independently.  Restart all three after replacing the
extension or changing the 9D certificate:

```sh
killall ctkbind 2>/dev/null || true
killall ctkahp 2>/dev/null || true
sudo killall ctkahp 2>/dev/null || true
killall ctkd 2>/dev/null || true
sudo killall ctkd 2>/dev/null || true
```

Unplug the YubiKey, reconnect it, and wait several seconds.  The services are
managed by `launchd` and start again on demand.

Check that the token and identities are visible:

```sh
security list-smartcards
sc_auth identities
```

## 6. Pair slot 9A with the macOS account

Copy the public-key hash belonging to the slot-9A authentication certificate
from `sc_auth identities`, then pair it:

```sh
ACCOUNT_NAME="$(id -un)"
LOGIN_HASH="PASTE_THE_SLOT_9A_PUBLIC_KEY_HASH"
sudo sc_auth pair -v -u "$ACCOUNT_NAME" -h "$LOGIN_HASH"
```

Touch the YubiKey when it flashes.  A successful result must not contain
either of these warnings:

```text
Failed to store Login keychain unlock key.
user password will be required after next SmartCard login
```

Verify the persisted pairing:

```sh
sc_auth list -v -u "$ACCOUNT_NAME"
```

If pairing succeeds but keychain wrapping fails, unpair, repeat the complete
cache refresh in step 5, reconnect the YubiKey, and pair again:

```sh
sudo sc_auth unpair -u "$ACCOUNT_NAME" -h "$LOGIN_HASH"
```

Do not regenerate either key merely to clear a stale CryptoTokenKit cache.

## 7. Test login and keychain unlock

1. Keep the YubiKey connected.
2. Lock the Mac with Control-Command-Q.
3. Submit the smart-card credential field so macOS starts authentication.
4. Touch the YubiKey when it requests the 9A operation.  A second touch may be
   requested for the 9D keychain unwrap, depending on the 9D touch policy and
   cache timing.
5. Confirm that the desktop unlocks and that no separate Login keychain
   password dialog appears.

The field can still be labelled `PIN` because that UI belongs to macOS
`loginwindow`.  This patch suppresses CryptoTokenKit PIN authentication only
when the YubiKey itself reports `PIN policy: never`; it does not turn a YubiKey
into a biometric device or make a touch submit the login window.

For diagnostics, inspect recent logs:

```sh
log show --last 10m --style compact \
  --predicate '(process == "OpenSCToken") OR (process == "ctkbind") OR (process == "ctkahp")'
```

A successful pairing and keychain-wrap operation includes a successful
`storeUnlockKey` result and does not contain `No suitable key was found`.

## 8. Recovery and rollback

The account password remains the recovery method unless mandatory smart-card
enforcement was enabled separately.

Remove only the affected pairing:

```sh
sudo sc_auth unpair -u "$ACCOUNT_NAME" -h "$LOGIN_HASH"
```

Unregister OpenSCToken:

```sh
pluginkit -r \
  -i org.opensc-project.mac.opensctoken.OpenSCTokenApp.OpenSCToken
```

If `DisabledTokens` contains only the Apple PIV identifier added in step 4,
restore the built-in PIV driver with:

```sh
sudo defaults delete \
  /Library/Preferences/com.apple.security.smartcard DisabledTokens
```

If other entries existed, restore the original array instead of deleting the
whole preference.  Refresh the CryptoTokenKit services again and reconnect
the YubiKey after changing drivers.

Restoring an exported certificate does not restore its old private key.  A
slot private key is recoverable only when it was imported originally and its
source key was backed up separately.
