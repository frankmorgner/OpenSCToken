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

- OpenSC installed and compiled with CryptoTokenKit
- Xcode 8.0 or later; macOS 10.12 SDK or later
- Code signing credentials

```
# Build basic version of OpenSC with CryptoTokenKit
git clone https://github.com/OpenSC/OpenSC.git
cd OpenSC
./bootstrap
# We disable dependencies here, but at some point we should integrate with `../MacOSX/build`, which builds all of them
./configure --disable-pcsc  --enable-cryptotokenkit \
    --disable-openssl --disable-readline --disable-zlib --prefix=/Library/OpenSC
make install DESTDIR=${PWD}/target

# Now build OpenSCToken
git clone http://github.com/frankmorgner/OpenSCToken.git
xcodebuild -target OpenSCTokenApp -configuration Release -project OpenSCToken/OpenSCTokenApp.xcodeproj install DSTROOT=${PWD}/target
```

## Running OpenSCToken

OpenSCToken requires macOS 10.12 or later. For running the plug-in, you have three options:

1. `open target/Library/OpenSC/OpenSCTokenApp.app`
Runs the hosting application. Your token will be **available while the app is running**.

2. `pluginkit -a target/Library/OpenSC/OpenSCTokenApp.app/Contents/PlugIns/OpenSCToken.appex`
Registers OpenSC in the PlugInKit subsystem for the current user. Your token will be **available after login**.

3. `sudo cp -r target/Library/OpenSC/OpenSCTokenApp.app/Contents/PlugIns/OpenSCToken.appex /System/Library/Frameworks/CryptoTokenKit.framework/PlugIns`
Registers OpenSC globally. Your token **will always be available**. Copying the plug-in requires *security integrity protection* to be disabled.

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
