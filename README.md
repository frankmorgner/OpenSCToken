# OpenSCToken: Use OpenSC in CryptoTokenKit

CryptoTokenKit is Apple's take on programmatic access to smart cards and other tokens. It provides both low level access to tokens (comparable with PC/SC) and high level access for system wide integration of a token (comparable with Windows Smart Card Minidriver).

For further information about smart cards in macOS please read the following ressources:

- [Apple's guide on smart card integration](https://support.apple.com/guide/deployment/depd0b888248) (open the table of contents to access the pages on smart card logon, FileVault usage and more extended options)
- [`man 8 security`](http://www.manpagez.com/man/1/security/)
- [`man 8 sc_auth`](http://www.manpagez.com/man/8/sc_auth/)
- [`man 8 SmartCardServices`](http://www.manpagez.com/man/7/SmartCardServices/)

OpenSCToken aims at providing the existing functionality of OpenSC through CryptoTokenKit.

## Quickstart

1. Download [the latest release of OpenSCToken](https://github.com/frankmorgner/OpenSCToken/releases/latest)
2. Open the image (`.dmg` file) and drag *OpenSCTokenApp* to your *Applications*
3. Launching *OpenSCTokenApp* shows an empty application and registers the token driver.

Now your're ready to use the smart card even if the application is not running (as long as your card is supported by OpenSC).

### Useful Commands

- Show location of the registered OpenSCToken
```
pluginkit -v -m -D -i org.opensc-project.mac.opensctoken.OpenSCTokenApp.OpenSCToken
```
- List available smart cards and paired/unpaired identities:
```
sc_auth identities
```
- Pair a smart card with your account:
```
sc_auth pair ${HASH}
```
- Remove paired smart card from your account:
```
sc_auth unpair ${HASH}
```
- Disable dialog for pairing a smart card with the current account:
```
sc_auth pairing_ui -s disable
```
- Disable macOS' built-in token driver for the PIV card (Yubikey) to use use OpenSC instead:
```
sudo defaults write /Library/Preferences/com.apple.security.smartcard DisabledTokens -array com.apple.CryptoTokenKit.pivtoken
```
- Enable macOS' built-in token driver for the PIV card (Yubikey):
```
sudo defaults delete /Library/Preferences/com.apple.security.smartcard DisabledTokens
```
- Unregister OpenSCToken
```
pluginkit -r -i org.opensc-project.mac.opensctoken.OpenSCTokenApp.OpenSCToken
```

## Comparison with [OpenSC.tokend](https://github.com/OpenSC/OpenSC.tokend)

- [x] OpenSCToken supports multiple certificates, keys and PINs
- [x] OpenSCToken has propper support for PIN pad on reader or token
- [x] OpenSCToken offers easy login with smart card and automatically unlocks the *login keychain*
- [ ] Tokens are not visible in *Keychain Access* anymore (use `sc_auth`/`security` from command line instead)

## Building OpenSCToken

Requirements:

- Xcode 8.0 or later; macOS 10.12 SDK or later
- help2man, gengetopt
- Code signing credentials

```
# Install dependencies
brew install help2man
brew install gengetopt
brew install automake 

# Checkout OpenSCToken
git clone http://github.com/frankmorgner/OpenSCToken.git

# Checkout and build all dependencies (i.e. OpenSSL, OpenPACE and OpenSC)
cd OpenSCToken
./bootstrap

# Now build OpenSCTokenApp
xcodebuild -target OpenSCTokenApp -configuration Release -project OpenSCTokenApp.xcodeproj install DSTROOT=${PWD}/build
```

Once all dependencies are built, the project can be executed and debugged from Xcode. Running the application, adds OpenSCToken to the system's plug-in registry. After insterting a token, attach to the process `OpenSCToken` for debugging with Xcode.

## Running OpenSCToken

OpenSCToken requires macOS 10.12 or later. For registering the token driver, you have two options:

1. Run *OpenSCTokenApp* or execute `pluginkit -a /Applications/Utilities/OpenSCTokenApp.app/Contents/PlugIns/OpenSCToken.appex`:
Registers OpenSC in the PlugInKit subsystem for the current user. Your token will be **available after login**. Note that database clean-ups may eventually remove the plug-in.

2. Run *OpenSCTokenApp* as SecurityAgent `sudo -u _securityagent /Applications/Utilities/OpenSCTokenApp.app/Contents/MacOS/OpenSCTokenApp` or execute `sudo -u _securityagent pluginkit -a /Applications/Utilities/OpenSCTokenApp.app/Contents/PlugIns/OpenSCToken.appex`:
Registers OpenSC globally. Your token **will always be available**.

## Configuring OpenSCToken

OpenSCToken supports all configuration options from OpenSC. However, you need to make sure that files to be read or written are available from the token driver's sandbox.

For example, `opensc.conf`, which is read by OpenSC, is available in `/Applications/Utilities/OpenSCTokenApp.app/Contents/PlugIns/OpenSCToken.appex/Contents/Resources`. When using configuration options that need to write a file (e.g. `debug_file` or `file_cache_dir`), you need to make sure this is done in the token driver's `Documents` directory (e.g. something like `~/Library/Containers/org.opensc-project.mac.opensctoken.OpenSCTokenApp.OpenSCToken/Data/Documents`). For your convenience, these locations are written to the system log when OpenSCToken is started with a smart card. Use the following commands to view the log:

```
sudo log config --mode "private_data:on"
log stream --predicate 'senderImagePath contains[cd] "OpenSCToken"'
```

On macOS Catalina and later, the mode "private_data:on" is not available anymore and instead you to [create and import a logging profile](https://superuser.com/a/1532052).

## Test Results

Tested applications:

- [x] Login to macOS
- [x] Unlock screen saver
- [x] Unlock *login keychain*
- [x] Safari, Chrome, Firefox (TLS client authentication)
- [x] Unlock *sudo*

Tested Mechanisms:

- [x] `kSecKeyAlgorithmRSASignatureRaw`
- [ ] `kSecKeyAlgorithmRSAEncryptionRaw`
- [ ] `kSecKeyAlgorithmECDSASignatureRFC4754`
- [ ] `kSecKeyAlgorithmECDSASignatureDigestX962`
- [x] `kSecKeyAlgorithmECDSASignatureDigestX962SHA1`
- [x] `kSecKeyAlgorithmECDSASignatureDigestX962SHA224`
- [x] `kSecKeyAlgorithmECDSASignatureDigestX962SHA256`
- [x] `kSecKeyAlgorithmECDSASignatureDigestX962SHA384`
- [x] `kSecKeyAlgorithmECDSASignatureDigestX962SHA512`

The unchecked mechanisms are implemented, but currently untested.

---

Copyright (C) 2017-2019 Frank Morgner <frankmorgner@gmail.com>
