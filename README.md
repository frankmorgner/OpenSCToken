# OpenSCToken: Use OpenSC in CryptoTokenKit

CryptoTokenKit is Apple's take on programmatic access to smart cards and other tokens. It provides both low level access to tokens (comparable with PC/SC) and high level access for system wide integration of a token (comparable with Windows Smart Card Minidriver).

For further information about CryptoTokenKit please read the following ressources:

- [`man 8 security`](http://www.manpagez.com/man/1/security/)
- [`man 8 sc_auth`](http://www.manpagez.com/man/8/sc_auth/)
- [`man 8 SmartCardServices`](http://www.manpagez.com/man/7/SmartCardServices/)
- [Use Mandatory Smart Card Authentication](https://support.apple.com/en-us/HT208372)
- [*Working with Smart Cards: macOS and Security*](http://www.macad.uk/presentations/Richard_Purves_SC.pdf)

OpenSCToken aims at providing the existing functionality of OpenSC through CryptoTokenKit.

## Comparison with [OpenSC.tokend](https://github.com/OpenSC/OpenSC.tokend)

- [x] Supports multiple certificates, keys and PINs
- [x] Propper support for PIN pad on reader or token
- [x] Easy login with smart card and automatically unlock the *login keychain*
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

Once all dependencies are available at the correct locations (via `./bootstrap`), the project can be executed and debugged from Xcode. Running the App, adds OpenSCToken to the system's plug-in registry. After insterting a token, attach to the process `OpenSCToken` for debugging with Xcode.

## Running OpenSCToken

OpenSCToken requires macOS 10.12 or later. For running the plug-in, you have three options:

1. `open build/Applications/OpenSCTokenApp.app`
Runs the hosting application. Your token will be **available while the app is running**.

2. `pluginkit -a build/Applications/OpenSCTokenApp.app/Contents/PlugIns/OpenSCToken.appex`
Registers OpenSC in the PlugInKit subsystem for the current user. Your token will be **available after login**. Note that database clean-ups may eventually remove the plug-in.

3. `sudo cp -r build/Applications/OpenSCTokenApp.app/Contents/PlugIns/OpenSCToken.appex /System/Library/Frameworks/CryptoTokenKit.framework/PlugIns`
Registers OpenSC globally. Your token **will always be available**. Copying the plug-in requires *security integrity protection (SIP)* to be disabled.

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

---

Copyright (C) 2017 Frank Morgner <frankmorgner@gmail.com>
