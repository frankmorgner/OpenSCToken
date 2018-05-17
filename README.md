# OpenSCToken: Use OpenSC in CryptoTokenKit

CryptoTokenKit is Apple's take on programmatic access to smart cards and other tokens. It provides both low level access to tokens (comparable with PC/SC) and high level access for system wide integration of a token (comparable with Windows Smart Card Minidriver).

For further information about CryptoTokenKit please read the following ressources:

- [`man 8 security`](http://www.manpagez.com/man/1/security/)
- [`man 8 sc_auth`](http://www.manpagez.com/man/8/sc_auth/)
- [`man 8 SmartCardServices`](http://www.manpagez.com/man/7/SmartCardServices/)
- [Use Mandatory Smart Card Authentication](https://support.apple.com/en-us/HT208372)
- [*Working with Smart Cards: macOS and Security*](http://www.macad.uk/presentations/Richard_Purves_SC.pdf)

OpenSCToken aims at providing the existing functionality of OpenSC through CryptoTokenKit.

## Quickstart

1. Download [the latest release of OpenSCToken](https://github.com/frankmorgner/OpenSCToken/releases/latest)
2. Open the image (`.dmg` file) and drag `OpenSCToken` to your `Applications`
3. Opening `OpenSCToken` you'll see an empty application which is needed once to register the token driver for your user account.

When the token driver has been registered in the system, your smart card should be available even if the application is not running (as long as your card is supported by OpenSC).

## Comparison with [OpenSC.tokend](https://github.com/OpenSC/OpenSC.tokend)

- [x] OpenSCToken supports multiple certificates, keys and PINs
- [x] OpenSCToken has propper support for PIN pad on reader or token
- [x] OpenSCToken offers easy login with smart card and automatically unlocks the *login keychain*
- [ ] Tokens are not visible in *Keychain Access* anymore (use `sc_auth`/`security` from command line instead)
- [ ] Most non-Apple applications do not yet support CryptoTokenKit. If OpenSCToken is used together with OpenSC.tokend, your token will appear twice in Safari and other Apple-apps.

## Building OpenSCToken

Requirements:

- Xcode 8.0 or later; macOS 10.12 SDK or later
- Code signing credentials

```
# Checkout OpenSCToken
git clone http://github.com/frankmorgner/OpenSCToken.git

# Checkout and build all dependencies (i.e. OpenSSL, OpenPACE and OpenSC)
cd OpenSCToken
./bootstrap

# Now build OpenSCTokenApp
xcodebuild -target OpenSCTokenApp -configuration Release -project OpenSCToken/OpenSCTokenApp.xcodeproj install DSTROOT=${PWD}/build
```

Once all dependencies are built, the project can be executed and debugged from Xcode. Running the application, adds OpenSCToken to the system's plug-in registry. After insterting a token, attach to the process `OpenSCToken` for debugging with Xcode.

## Running OpenSCToken

OpenSCToken requires macOS 10.12 or later. For registering the token driver, you have two options:

1. `open build/Applications/OpenSCTokenApp.app` or run `pluginkit -a build/Applications/OpenSCTokenApp.app/Contents/PlugIns/OpenSCToken.appex`:
Registers OpenSC in the PlugInKit subsystem for the current user. Your token will be **available after login**. Note that database clean-ups may eventually remove the plug-in.

2. `sudo cp -r build/Applications/OpenSCTokenApp.app/Contents/PlugIns/OpenSCToken.appex /System/Library/Frameworks/CryptoTokenKit.framework/PlugIns`:
Registers OpenSC globally. Your token **will always be available**. Copying the plug-in requires *security integrity protection (SIP)* to be disabled.

## Configuring OpenSCToken

OpenSCToken supports all configuration options from OpenSC. However, you need to make sure that files to be read or written are available from the token driver's sandbox.

For example, `opensc.conf`, which is read by OpenSC, is available in `OpenSCTokenApp.app/Contents/PlugIns/OpenSCToken.appex/Contents/Resources`. When using configuration options that need to write a file (e.g. `debug_file` or `file_cache_dir`), you need to make sure this is done in the token driver's `Documents` directory (e.g. something like `~/Library/Containers/org.opensc-project.mac.opensctoken.OpenSCTokenApp.OpenSCToken/Data/Documents`). For your convenience, these locations are written to the system log when OpenSCToken is started with a smart card. Use the following commands to view the log:

```
sudo log config --mode "private_data:on"
log stream --predicate 'senderImagePath contains[cd] "OpenSCToken"'
```

## Test Results

Tested applications:

- [x] Login to macOS with smart card
- [x] Unlock *login keychain*
- [x] Safari (TLS client authentication)

Tested Mechanisms:

- [x] `kSecKeyAlgorithmRSASignatureRaw`
- [ ] `kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA1`
- [ ] `kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA224`
- [ ] `kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA256`
- [ ] `kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA384`
- [ ] `kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA512`
- [ ] `kSecKeyAlgorithmECDSASignatureDigestX962SHA1`
- [ ] `kSecKeyAlgorithmECDSASignatureMessageX962SHA224`
- [ ] `kSecKeyAlgorithmECDSASignatureDigestX962SHA256`
- [ ] `kSecKeyAlgorithmECDSASignatureDigestX962SHA384`
- [ ] `kSecKeyAlgorithmECDSASignatureDigestX962SHA512`
- [ ] `kSecKeyAlgorithmRSAEncryptionRaw`
- [ ] `kSecKeyAlgorithmRSAEncryptionPKCS1`

The unchecked mechanisms are implemented, but currently untested.

---

Copyright (C) 2017 Frank Morgner <frankmorgner@gmail.com>
