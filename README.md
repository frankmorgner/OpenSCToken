# OpenSCToken: Use OpenSC in CryptoTokenKit

Running the hosting application in Xcode automatically inserts the new extension into CryptoTokenKit. For permanent installation copy the extension to `/System/Library/Frameworks/CryptoTokenKit.framework/PlugIns/`.

For further information please read the following ressources:

- [`man 8 security`](http://www.manpagez.com/man/1/security/)
- [`man 8 sc_auth`](http://www.manpagez.com/man/8/sc_auth/)
- [`man 8 SmartCardServices`](http://www.manpagez.com/man/7/SmartCardServices/)
- [*Working with Smart Cards: macOS and Security*](http://www.macad.uk/presentations/Richard_Purves_SC.pdf)

## Comparison with [OpenSC.tokend](https://github.com/OpenSC/OpenSC.tokend)

- [x] Supports multiple certificates, keys and PINs
- [x] Propper support for PIN pad on reader or token
- [x] Easy login with smart card and automatically unlock the *login keychain*
- [ ] Tokens are not visible in *Keychain Access* anymore (use `sc_auth`/`security` from command line instead)
- [ ] Most non-Apple applications do not yet support CryptoTokenKit. If OpenSCToken is used together with OpenSC.tokend, your token will appear twice in Safari and other Apple-apps.

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

## Requirements

Needs OpenSC installed and compiled with CryptoTokenKit:

```
./configure --disable-pcsc  --enable-cryptotokenkit
```

### Build

Xcode 8.0 or later; iOS 10.0 SDK or later

### Runtime

iOS 10.0 or later

Copyright (C) 2017 Frank Morgner <frankmorgner@gmail.com>
