/*
 * Copyright (C) 2017 Frank Morgner <frankmorgner@gmail.com>
 *
 * This file is part of OpenSCToken.
 *
 * This library is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * OpenSCToken is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * OpenSCToken.  If not, see <http://www.gnu.org/licenses/>.
 */
#import <os/log.h>
#import <Foundation/Foundation.h>
#import <CryptoTokenKit/CryptoTokenKit.h>
#import <Security/SecAsn1Coder.h>

#import "Token.h"
#import "TokenSession.h"

#include "libopensc/log.h"
#include "libopensc/pkcs15.h"
#include "ui/strings.h"
#include "ui/notify.h"

typedef struct {
    SecAsn1Item r;
    SecAsn1Item s;
} RawECDSASignature;

static const SecAsn1Template DerECDSASignatureTemplate[] = {
    { SEC_ASN1_SEQUENCE, 0, nil, sizeof(RawECDSASignature) },
    { SEC_ASN1_INTEGER, offsetof(RawECDSASignature, r) },
    { SEC_ASN1_INTEGER, offsetof(RawECDSASignature, s) },
    { 0 }
};

static unsigned int algorithmToFlags(TKTokenKeyAlgorithm * algorithm)
{
    if ([algorithm isAlgorithm:kSecKeyAlgorithmRSAEncryptionRaw]
        || [algorithm isAlgorithm:kSecKeyAlgorithmRSASignatureRaw])
        return SC_ALGORITHM_RSA_RAW;

    if ([algorithm isAlgorithm:kSecKeyAlgorithmECDSASignatureRFC4754]
        || [algorithm isAlgorithm:kSecKeyAlgorithmECDSASignatureDigestX962]
        || [algorithm isAlgorithm:kSecKeyAlgorithmECDSASignatureDigestX962SHA1]
        || [algorithm isAlgorithm:kSecKeyAlgorithmECDSASignatureDigestX962SHA224]
        || [algorithm isAlgorithm:kSecKeyAlgorithmECDSASignatureDigestX962SHA256]
        || [algorithm isAlgorithm:kSecKeyAlgorithmECDSASignatureDigestX962SHA384]
        || [algorithm isAlgorithm:kSecKeyAlgorithmECDSASignatureDigestX962SHA512])
        return SC_ALGORITHM_ECDSA_HASH_NONE;

    return (unsigned int) -1;
}

static void statusToError(int sc_status, NSError **error)
{
    if (error != nil) {
        switch (sc_status) {
            case SC_ERROR_NOT_ALLOWED:
                /* fall through */
            case SC_ERROR_SECURITY_STATUS_NOT_SATISFIED:
                *error = [NSError errorWithDomain:TKErrorDomain code:TKErrorCodeAuthenticationNeeded userInfo:nil];
                break;
            case SC_ERROR_PIN_CODE_INCORRECT:
                *error = [NSError errorWithDomain:TKErrorDomain code:TKErrorCodeAuthenticationFailed userInfo:nil];
                break;
        }
    }
}

static BOOL sessionNeedsAuthentication(OpenSCTokenSession *session, struct sc_pkcs15_object *obj)
{
    if (session && session.smartCard.sensitive == NO && obj && 0 < obj->auth_id.len) {
        /* Some cards do not support a logout and CTK doesn't support a card reset. Since we want to enforce a PIN verification even though the key is technically unlocked, we do NOT use sc_pkcs15_get_pin_info() here. */
        if (obj->user_consent)
            session.needs_user_consent = YES;
        else
            session.needs_user_consent = NO;
        return YES;
    }

    return NO;
}

static BOOL OpenSCAuthOperationFinishWithError(OpenSCTokenSession *session, NSData *authID, NSString *PIN, NSError **error) {
    
    struct sc_pkcs15_object *pin_obj = NULL;
    struct sc_pkcs15_id p15id = dataToId(authID);
    int r = sc_pkcs15_find_pin_by_auth_id(session.OpenSCToken.p15card, &p15id, &pin_obj);
    LOG_TEST_GOTO_ERR(session.OpenSCToken.ctx, r, "Could not find PIN object");
    
    const char *pin = NULL;
    size_t pin_len = 0;
    if (PIN) {
        pin = [PIN UTF8String];
        pin_len = strlen(pin);
    }

    /*
     * Do what PKCS#11 would do for keys requiring CKA_ALWAYS_AUTHENTICATE
     * and CKU_CONTEXT_SPECIFIC login to let driver know this verify will be followed by
     * a crypto operation.  Card drivers can test for SC_AC_CONTEXT_SPECIFIC
     * to do any special handling.
     */
    if (session.needs_user_consent) {
        int auth_meth_saved;
        struct sc_pkcs15_auth_info *pinfo = (struct sc_pkcs15_auth_info *) pin_obj->data;

        auth_meth_saved = pinfo->auth_method;

        pinfo->auth_method = SC_AC_CONTEXT_SPECIFIC;
        r = sc_pkcs15_verify_pin(session.OpenSCToken.p15card, pin_obj, (const unsigned char *) pin, pin_len);
        pinfo->auth_method = auth_meth_saved;
    } else
        r = sc_pkcs15_verify_pin(session.OpenSCToken.p15card, pin_obj, (const unsigned char *) pin, pin_len);
    
err:
    if (SC_SUCCESS != r) {
        os_log_error(OS_LOG_DEFAULT, "Could not verify PIN %s", sc_strerror(r));
        return NO;
    }
    // Mark card session sensitive, because we entered PIN into it and no session should access it in this state.
    session.smartCard.sensitive = YES;

    return YES;
}

@implementation OpenSCAuthOperation

- (instancetype)initWithSession:(OpenSCTokenSession *)session authID:(NSData *)authID{
    if (self = [super init]) {
        _session = session;
        _authID = authID;
    }
    
    return self;
}

- (BOOL)finishWithError:(NSError * _Nullable __autoreleasing *)error {
    return OpenSCAuthOperationFinishWithError(self.session, _authID, self.PIN, error);
}

@end

@implementation OpenSCPINPadAuthOperation

- (instancetype)initWithSession:(OpenSCTokenSession *)session authID:(NSData *)authID{
    if (self = [super init]) {
        const char *title = ui_get_str(
          session.OpenSCToken.ctx,
          &session.OpenSCToken.p15card->card->reader->atr,
          session.OpenSCToken.p15card,
          MD_PINPAD_DLG_MAIN);
        const char *text = ui_get_str(
          session.OpenSCToken.ctx,
          &session.OpenSCToken.p15card->card->reader->atr,
          session.OpenSCToken.p15card,
          MD_PINPAD_DLG_CONTENT_USER);

        sc_notify(title, text);

        _session = session;
        _authID = authID;
    }
    
    return self;
}

- (BOOL)finishWithError:(NSError * _Nullable __autoreleasing *)error {
    return OpenSCAuthOperationFinishWithError(self.session, _authID, nil, error);
}

@end

@implementation OpenSCTokenSession

- (instancetype)initWithToken:(OpenSCToken *)token {
    if (self = [super initWithToken:token]) {
        _OpenSCToken = token;
    }
    return self;
}

- (TKTokenAuthOperation *)tokenSession:(TKTokenSession *)session beginAuthForOperation:(TKTokenOperation)operation constraint:(TKTokenOperationConstraint)constraint error:(NSError * _Nullable __autoreleasing *)error {
    if ((self.OpenSCToken.p15card->card->reader->capabilities & SC_READER_CAP_PIN_PAD)
        || (self.OpenSCToken.p15card->card->caps & SC_CARD_CAP_PROTECTED_AUTHENTICATION_PATH))
        return [[OpenSCPINPadAuthOperation alloc] initWithSession:self authID:constraint];
    else
        return [[OpenSCAuthOperation alloc] initWithSession:self authID:constraint];
}

/* copied from pkcs15-cardos.c */
#define USAGE_ANY_SIGN      (SC_PKCS15_PRKEY_USAGE_SIGN | SC_PKCS15_PRKEY_USAGE_NONREPUDIATION)
#define USAGE_ANY_DECIPHER  (SC_PKCS15_PRKEY_USAGE_DECRYPT | SC_PKCS15_PRKEY_USAGE_UNWRAP)
#define USAGE_ANY_AGREEMENT (SC_PKCS15_PRKEY_USAGE_DERIVE)

- (BOOL)tokenSession:(TKTokenSession *)session supportsOperation:(TKTokenOperation)operation usingKey:(TKTokenObjectID)keyObjectID algorithm:(TKTokenKeyAlgorithm *)algorithm {
    sc_log(self.OpenSCToken.ctx, "Check support of %s for key %s", algorithm.description.UTF8String, sc_dump_hex([keyObjectID bytes], [keyObjectID length]));

    struct sc_pkcs15_id p15id = dataToId(keyObjectID);
    struct sc_pkcs15_object *prkey_obj = NULL;

    if (SC_SUCCESS != sc_pkcs15_find_prkey_by_id(self.OpenSCToken.p15card, &p15id, &prkey_obj))
        return NO;
    
    struct sc_pkcs15_prkey_info *prkey_info = (struct sc_pkcs15_prkey_info *) prkey_obj->data;
    switch (operation) {
        case TKTokenOperationSignData:
            if (!(USAGE_ANY_SIGN & prkey_info->usage))
                return NO;
            break;
        case TKTokenOperationDecryptData:
            if (!(USAGE_ANY_DECIPHER & prkey_info->usage))
                return NO;
            break;
        default:
            return NO;
    }
    
    unsigned int minimum_flags = algorithmToFlags(algorithm);
    sc_algorithm_info_t *alg_info;
    switch (prkey_obj->type) {
        case SC_PKCS15_TYPE_PRKEY_RSA:
            alg_info = sc_card_find_rsa_alg(self.OpenSCToken.card, (unsigned int) prkey_info->modulus_length);
            break;
        case SC_PKCS15_TYPE_PRKEY_EC:
            alg_info = sc_card_find_ec_alg(self.OpenSCToken.card, (unsigned int) prkey_info->field_length, NULL);
            break;
        default:
            return NO;
    }
    if (!alg_info || ((alg_info->flags & minimum_flags) != minimum_flags))
        return NO;
    /* TODO in addition with inspecting the card's flags we should check the
     * TokenInfo's and the private key's supported PKCS#11 mechanisms, see
     * pkcs15_prkey_can_do() in src/pkcs11/framework-pkcs15.c
     * TODO add more of the supported signature schemes (PSS/OAEP/PKCS1)
     */
    
    sc_log(self.OpenSCToken.ctx, "Algorithm is supported.");

    return YES;
}

- (NSData *)tokenSession:(TKTokenSession *)session signData:(NSData *)dataToSign usingKey:(TKTokenObjectID)keyObjectID algorithm:(TKTokenKeyAlgorithm *)algorithm error:(NSError * _Nullable __autoreleasing *)error {
    sc_log(self.OpenSCToken.ctx, "Performing %s with key %s", algorithm.description.UTF8String, sc_dump_hex([keyObjectID bytes], [keyObjectID length]));
    sc_log_hex(self.OpenSCToken.ctx, "data to sign", [dataToSign bytes], [dataToSign length]);

    struct sc_pkcs15_id p15id = dataToId(keyObjectID);
    struct sc_pkcs15_object *prkey_obj = NULL;
    if (SC_SUCCESS != sc_pkcs15_find_prkey_by_id(self.OpenSCToken.p15card, &p15id, &prkey_obj))
        return nil;

    if (sessionNeedsAuthentication(self, prkey_obj)) {
        *error = [NSError errorWithDomain:TKErrorDomain code:TKErrorCodeAuthenticationNeeded userInfo:nil];
        return nil;
    }

    /* Compute output size */
    NSMutableData *out;
    struct sc_pkcs15_prkey_info *prkey_info = (struct sc_pkcs15_prkey_info *) prkey_obj->data;
    switch (prkey_obj->type) {
        case SC_PKCS15_TYPE_PRKEY_RSA:
            out = [NSMutableData dataWithLength:prkey_info->modulus_length / 8];
            break;
        case SC_PKCS15_TYPE_PRKEY_EC:
            switch(prkey_info->field_length) {
                case 256:
                    /* ECDSA_P256 */
                    out = [NSMutableData dataWithLength:256 / 8 * 2];
                    break;
                case 384:
                    /* ECDSA_P384 */
                    out = [NSMutableData dataWithLength:384 / 8 * 2];
                    break;
                case 512:
                    /* ECDSA_P512 special case !!! */
                    out = [NSMutableData dataWithLength:132];
                    break;
                default:
                    return nil;
            }
            break;
        default:
            return nil;
    }
    int r = sc_pkcs15_compute_signature(self.OpenSCToken.p15card, prkey_obj, algorithmToFlags(algorithm), [dataToSign bytes], [dataToSign length], (unsigned char *) [out bytes], [out length], NULL);

    if (0 > r) {
        statusToError(r, error);
        return nil;
    }
    [out setLength:(size_t) r];
    
    if (prkey_obj->type == SC_PKCS15_TYPE_PRKEY_EC) {
        SecAsn1CoderRef asn1Coder;
        SecAsn1CoderCreate(&asn1Coder);
        
        SecAsn1Item derOut = {0, nil};
        uint8 *outBytes = (uint8*)[out bytes];
        RawECDSASignature rawECDSASignature = {
            { [out length] / 2, outBytes },
            { [out length] / 2, outBytes + ([out length] / 2) },
        };
        
        OSStatus ret = SecAsn1EncodeItem(asn1Coder, &rawECDSASignature, DerECDSASignatureTemplate, &derOut);
        if (ret == errSecSuccess) {
            out = [NSMutableData dataWithBytes:derOut.Data length:derOut.Length];
        }
        else {
            out = nil;
        }
        SecAsn1CoderRelease(asn1Coder);
    }
    
    return out;
}

- (NSData *)tokenSession:(TKTokenSession *)session decryptData:(NSData *)ciphertext usingKey:(TKTokenObjectID)keyObjectID algorithm:(TKTokenKeyAlgorithm *)algorithm error:(NSError * _Nullable __autoreleasing *)error {
    sc_log(self.OpenSCToken.ctx, "Performing %s with key %s", algorithm.description.UTF8String, sc_dump_hex([keyObjectID bytes], [keyObjectID length]));
    sc_log_hex(self.OpenSCToken.ctx, "cipher text", [ciphertext bytes], [ciphertext length]);

    struct sc_pkcs15_id p15id = dataToId(keyObjectID);
    struct sc_pkcs15_object *prkey_obj = NULL;
    if (SC_SUCCESS != sc_pkcs15_find_prkey_by_id(self.OpenSCToken.p15card, &p15id, &prkey_obj))
        return nil;
    
    if (sessionNeedsAuthentication(self, prkey_obj)) {
        *error = [NSError errorWithDomain:TKErrorDomain code:TKErrorCodeAuthenticationNeeded userInfo:nil];
        return nil;
    }

	unsigned char decrypted[512]; /* FIXME: Will not work for keys above 4096 bits */
	int r = sc_pkcs15_decipher(self.OpenSCToken.p15card, prkey_obj, algorithmToFlags(algorithm),
			[ciphertext bytes], [ciphertext length], decrypted, sizeof(decrypted), NULL);
    if (0 > r) {
        statusToError(r, error);
        return nil;
    }

    return [NSData dataWithBytes:decrypted length:(size_t) r];
}

- (NSData *)tokenSession:(TKTokenSession *)session performKeyExchangeWithPublicKey:(NSData *)otherPartyPublicKeyData usingKey:(TKTokenObjectID)keyObjectID algorithm:(TKTokenKeyAlgorithm *)algorithm parameters:(TKTokenKeyExchangeParameters *)parameters error:(NSError * _Nullable __autoreleasing *)error {
    return nil;
}

- (void)dealloc {
    /* logout to avoid the authentication to be misused */
    if (self.smartCard.sensitive) {
        if (SC_SUCCESS == sc_logout(self.OpenSCToken.card))
            self.smartCard.sensitive = NO;
    }
}

@end
