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
@import os.log;
@import Foundation;
@import CryptoTokenKit;
#import <CommonCrypto/CommonDigest.h>

#include "libopensc/log.h"
#include "libopensc/pkcs15.h"
#include "libopensc/../../config.h"
#include "eac/eac.h"

#import "Token.h"


@implementation TKTokenKeychainItem(OpenSCDataFormat)

- (void)setName:(NSString *)name {
    if (self.label != nil) {
        self.label = [NSString stringWithFormat:@"%@ (%@)", name, self.label];
    } else {
        self.label = name;
    }
}

@end


@implementation OpenSCToken

/* copied from pkcs15-cardos.c */
#define USAGE_ANY_SIGN      (SC_PKCS15_PRKEY_USAGE_SIGN | SC_PKCS15_PRKEY_USAGE_NONREPUDIATION)
#define USAGE_ANY_DECIPHER  (SC_PKCS15_PRKEY_USAGE_DECRYPT | SC_PKCS15_PRKEY_USAGE_UNWRAP)
#define USAGE_ANY_AGREEMENT (SC_PKCS15_PRKEY_USAGE_DERIVE)

static void initializeInstanceIDFromKey(struct sc_pkcs15_card *p15card, struct sc_pkcs15_object *prkey_obj, NSString * _Nullable * _Nonnull instanceID) {
    if (instanceID == NULL || *instanceID != nil) {
        return;
    }
    unsigned char szGuid[SC_MD_MAX_CONTAINER_NAME_LEN + 1] = {0};
    size_t guid_len = sizeof(szGuid);
    int r = sc_pkcs15_get_object_guid(p15card, prkey_obj, 1, szGuid, &guid_len);
    if (r == SC_SUCCESS) {
        *instanceID = [[NSString alloc] initWithBytes:szGuid
                                               length:guid_len
                                             encoding:NSUTF8StringEncoding];
    }
}

static void configureKeyConstraintsAndUsage(TKTokenKeychainKey *keyItem, struct sc_pkcs15_object *prkey_obj) {
    struct sc_pkcs15_prkey_info *prkey_info = (struct sc_pkcs15_prkey_info *) prkey_obj->data;
    NSMutableDictionary<NSNumber *, TKTokenOperationConstraint> *constraints = [NSMutableDictionary dictionary];
    TKTokenOperationConstraint constraint;
    if (prkey_obj->auth_id.len == 0) {
        /* true, indicating that the operation is always allowed, without any authentication necessary. */
        constraint = @YES;
    } else {
        /* Any other property list compatible value defined by the implementation of the token extension. Any such constraint is required to stay constant for the entire lifetime of the token. */
        constraint = idToData(TYPE_AUTH, &prkey_obj->auth_id);
    }

    if (USAGE_ANY_SIGN & prkey_info->usage) {
        keyItem.canSign = YES;
        constraints[@(TKTokenOperationSignData)] = constraint;
    } else {
        keyItem.canSign = NO;
    }
    keyItem.suitableForLogin = keyItem.canSign;

    if (USAGE_ANY_DECIPHER & prkey_info->usage) {
        keyItem.canDecrypt = YES;
        constraints[@(TKTokenOperationDecryptData)] = constraint;
    } else {
        keyItem.canDecrypt = NO;
    }

    if (USAGE_ANY_AGREEMENT & prkey_info->usage) {
        keyItem.canPerformKeyExchange = YES;
        constraints[@(TKTokenOperationPerformKeyExchange)] = constraint;
    } else {
        keyItem.canPerformKeyExchange = NO;
    }

    keyItem.constraints = constraints;
}

static void setPublicKeyForStandaloneKey(TKTokenKeychainKey *keyItem, struct sc_pkcs15_card *p15card, struct sc_pkcs15_prkey_info *prkey_info) {
    struct sc_pkcs15_object *pubkey_obj = NULL;
    struct sc_pkcs15_pubkey *pubkey = NULL;
    NSData *pubData = nil;
    sc_context_t *ctx = p15card->card->ctx;

    if (sc_pkcs15_find_pubkey_by_id(p15card, &prkey_info->id, &pubkey_obj) == SC_SUCCESS && pubkey_obj) {
        if (sc_pkcs15_read_pubkey(p15card, pubkey_obj, &pubkey) == SC_SUCCESS && pubkey) {
            if (pubkey->algorithm == SC_ALGORITHM_RSA) {
                u8 *buf = NULL;
                size_t buflen = 0;
                if (sc_pkcs15_encode_pubkey_rsa(ctx, &pubkey->u.rsa, &buf, &buflen) == SC_SUCCESS && buf && buflen > 0) {
                    pubData = [NSData dataWithBytes:buf length:buflen];
                    free(buf);
                }
            } else if (pubkey->algorithm == SC_ALGORITHM_EC) {
                if (pubkey->u.ec.ecpointQ.value && pubkey->u.ec.ecpointQ.len > 0) {
                    pubData = [NSData dataWithBytes:pubkey->u.ec.ecpointQ.value length:pubkey->u.ec.ecpointQ.len];
                }
            }
            if (keyItem.keySizeInBits == 0) {
                if (pubkey->algorithm == SC_ALGORITHM_RSA) {
                    keyItem.keySizeInBits = (NSInteger)(pubkey->u.rsa.modulus.len * 8);
                } else if (pubkey->algorithm == SC_ALGORITHM_EC) {
                    keyItem.keySizeInBits = (NSInteger)pubkey->u.ec.params.field_length;
                }
            }
            sc_pkcs15_free_pubkey(pubkey);
        }
    }

    if (pubData != nil) {
        keyItem.publicKeyData = pubData;
        unsigned char digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1([pubData bytes], (CC_LONG)[pubData length], digest);
        keyItem.publicKeyHash = [NSData dataWithBytes:digest length:sizeof(digest)];
    }
}

static TKTokenKeychainKey * _Nullable createKeychainKey(struct sc_pkcs15_card *p15card, struct sc_pkcs15_object *prkey_obj, SecCertificateRef _Nullable certificateRef, NSString * _Nullable name) {
    struct sc_pkcs15_prkey_info *prkey_info = (struct sc_pkcs15_prkey_info *) prkey_obj->data;
    NSData *keyID = idToData(TYPE_PRIV, &prkey_info->id);
    if (keyID == nil) {
        return nil;
    }

    TKTokenKeychainKey *keyItem = [[TKTokenKeychainKey alloc] initWithCertificate:certificateRef objectID:keyID];
    if (keyItem == nil) {
        return nil;
    }

    if (certificateRef == nil) {
        if (prkey_obj->type == SC_PKCS15_TYPE_PRKEY_RSA) {
            keyItem.keyType = (NSString *)kSecAttrKeyTypeRSA;
            keyItem.keySizeInBits = (NSInteger)prkey_info->modulus_length;
        } else if (prkey_obj->type == SC_PKCS15_TYPE_PRKEY_EC) {
            keyItem.keyType = (NSString *)kSecAttrKeyTypeECSECPrimeRandom;
            keyItem.keySizeInBits = (NSInteger)prkey_info->field_length;
        } else {
            return nil;
        }

        setPublicKeyForStandaloneKey(keyItem, p15card, prkey_info);
    }

    NSString *keyName = name;
    if (keyName == nil || keyName.length == 0) {
        if (prkey_obj->label[0] != '\0') {
            keyName = [NSString stringWithUTF8String:prkey_obj->label];
        }
    }
    if (keyName == nil || keyName.length == 0) {
        keyName = [NSString stringWithFormat:@"Key %s", sc_dump_hex(prkey_info->id.value, prkey_info->id.len)];
    }
    [keyItem setName:keyName];

    configureKeyConstraintsAndUsage(keyItem, prkey_obj);

    return keyItem;
}

- (nullable instancetype)initWithSmartCard:(TKSmartCard *)smartCard AID:(nullable NSData *)AID OpenSCDriver:(OpenSCTokenDriver *)tokenDriver error:(NSError * _Nullable __autoreleasing *)error {

    sc_context_param_t ctx_param = {0};
    sc_context_t *ctx = NULL;
    sc_card_t *card = NULL;
    sc_pkcs15_card_t *p15card = NULL;
    struct sc_app_info *app_generic = NULL;
    struct sc_aid *aid = NULL;
    struct sc_pkcs15_object *objs[32];
    int r;
    size_t i, cert_num, prkey_num;
    NSMutableArray<TKTokenKeychainItem *> *items;
    NSMutableSet<NSData *> *processedKeyIDs = nil;
    NSString *instanceID = nil;

    /* TODO: Move card and p15card to smartCard.context. smartCard.context would
     * automatically be set to nil if the card gets reset or the state gets
     * modified by a different session, see documentation for TKSmartCard */

    os_log(OS_LOG_DEFAULT, "%s", OPENSC_SCM_REVISION);

    /* Respect the App's sandbox; use only bundled resources */
    NSString *Resources = [[NSBundle mainBundle] resourcePath];
    NSString *opensc_conf = [[NSBundle mainBundle] pathForResource:@"opensc"
                                                            ofType:@"conf"];
    NSArray *Documents = NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES);
    os_log(OS_LOG_DEFAULT, "For logging and persistent data cache please use %@",
            Documents.lastObject);
    if (opensc_conf != nil) {
        os_log(OS_LOG_DEFAULT, "Reading configuration %@", opensc_conf);
        setenv("OPENSC_CONF", opensc_conf.fileSystemRepresentation, 0);
    }

    ctx_param.ver = 1;
    ctx_param.app_name = "cryptotokenkit";

    r = sc_context_create(&ctx, &ctx_param);
    if (r || !ctx)   {
        os_log_error(OS_LOG_DEFAULT, "sc_context_create: %s", sc_strerror(r));
        goto err;
    }

    r = sc_ctx_use_reader(ctx, (__bridge void *)(smartCard.slot), (__bridge void *)(smartCard));
    LOG_TEST_GOTO_ERR(ctx, r, "sc_ctx_use_reader");

    /* sc_ctx_use_reader() adds our handles to the end of the list of all readers */
    r = sc_connect_card(sc_ctx_get_reader(ctx, sc_ctx_get_reader_count(ctx)-1), &card);
    LOG_TEST_GOTO_ERR(ctx, r, "sc_connect_card");

    /* Initialize OpenPACE to access Resources within the App's sandbox. This initialization must happen after EAC_init() */
    if (Resources != nil) {
        EAC_set_cvc_default_dir(Resources.fileSystemRepresentation);
        EAC_set_x509_default_dir(Resources.fileSystemRepresentation);
    }

    app_generic = sc_pkcs15_get_application_by_type(card, "generic");
    aid = app_generic ? &app_generic->aid : NULL;
    r = sc_pkcs15_bind(card, aid, &p15card);
    LOG_TEST_GOTO_ERR(ctx, r, "sc_pkcs15_bind");

    /* some tokens do not report a serial number */
    if (p15card->tokeninfo && p15card->tokeninfo->serial_number &&
            p15card->tokeninfo->serial_number[0] != '\0') {
        instanceID =
            [NSString stringWithUTF8String:p15card->tokeninfo->serial_number];
    }

    r = sc_pkcs15_get_objects(p15card, SC_PKCS15_TYPE_CERT_X509, objs, sizeof(objs)/(sizeof *objs));
    LOG_TEST_GOTO_ERR(ctx, r, "sc_pkcs15_get_objects (SC_PKCS15_TYPE_CERT_X509)");
    cert_num = (size_t) r;
    items = [NSMutableArray arrayWithCapacity:cert_num];
    processedKeyIDs = [NSMutableSet set];
    for (i = 0; i < cert_num; i++) {
        struct sc_pkcs15_cert_info *cert_info = objs[i]->data;
        struct sc_pkcs15_cert *cert = NULL;
        struct sc_pkcs15_object *prkey_obj = NULL;
        int private_obj = objs[i]->flags & SC_PKCS15_CO_FLAG_PRIVATE;

        r = sc_pkcs15_read_certificate(p15card, cert_info, private_obj, &cert);
        if (r) {
            sc_log(ctx, "sc_pkcs15_read_certificate: %s", sc_strerror(r));
            continue;
        }
        NSData* certificateData = [NSData dataWithBytes:(const void *)cert->data.value length:sizeof(unsigned char)*cert->data.len];
        NSData* certificateID = idToData(TYPE_CERT, &cert_info->id);
        NSString *certificateName = [NSString stringWithUTF8String:objs[i]->label];
        id certificate = CFBridgingRelease(SecCertificateCreateWithData(kCFAllocatorDefault, (CFDataRef)certificateData));
        if (certificateData == nil || certificateID == nil || certificateName == nil || certificate == NULL) {
            sc_pkcs15_free_certificate(cert);
            continue;
        }
        TKTokenKeychainCertificate *certificateItem = [[TKTokenKeychainCertificate alloc] initWithCertificate:(__bridge SecCertificateRef)certificate objectID:certificateID];
        if (certificateItem == nil) {
            sc_pkcs15_free_certificate(cert);
            continue;
        }
        [certificateItem setName:certificateName];
        [items addObject:certificateItem];
        sc_pkcs15_free_certificate(cert);

        // Create key item.
        r = sc_pkcs15_find_prkey_by_id(p15card, &cert_info->id, &prkey_obj);
        if (r) {
            sc_log(ctx, "sc_pkcs15_find_prkey_by_id: %s", sc_strerror(r));
            continue;
        }
        TKTokenKeychainKey *keyItem = createKeychainKey(p15card, prkey_obj, (__bridge SecCertificateRef)certificate, certificateName);
        if (keyItem == nil) {
            continue;
        }

        [items addObject:keyItem];
        [processedKeyIDs addObject:keyItem.objectID];

        initializeInstanceIDFromKey(p15card, prkey_obj, &instanceID);
    }

    r = sc_pkcs15_get_objects(p15card, SC_PKCS15_TYPE_PRKEY, objs, sizeof(objs)/(sizeof *objs));
    LOG_TEST_GOTO_ERR(ctx, r, "sc_pkcs15_get_objects (SC_PKCS15_TYPE_PRKEY)");
    prkey_num = (size_t) r;
    for (i = 0; i < prkey_num; i++) {
        struct sc_pkcs15_object *prkey_obj = objs[i];
        struct sc_pkcs15_prkey_info *prkey_info = (struct sc_pkcs15_prkey_info *) prkey_obj->data;
        NSData* keyID = idToData(TYPE_PRIV, &prkey_info->id);
        if (keyID == nil || [processedKeyIDs containsObject:keyID]) {
            continue;
        }

        TKTokenKeychainKey *keyItem = createKeychainKey(p15card, prkey_obj, nil, nil);
        if (keyItem == nil) {
            continue;
        }

        [items addObject:keyItem];
        [processedKeyIDs addObject:keyItem.objectID];

        initializeInstanceIDFromKey(p15card, prkey_obj, &instanceID);
    }
    if (instanceID == nil) {
        // CryptoTokenKit requires a unique, persistent, non-empty instanceID to
        // generate a valid tokenID.
        goto err;
    }

    p15card->opts.use_pin_cache = 0;

    if (self = [super initWithSmartCard:smartCard AID:AID instanceID:instanceID tokenDriver:tokenDriver]) {
        [self.keychainContents fillWithItems:items];

        self.ctx = ctx;
        self.card = card;
        self.p15card = p15card;

        return self;
    }

err:
    sc_pkcs15_card_free(p15card);
    sc_disconnect_card(card);
    sc_release_context(ctx);

    return nil;
}

- (void)dealloc {
    sc_pkcs15_card_free(self.p15card);
    sc_disconnect_card(self.card);
    sc_release_context(self.ctx);
    self.card = NULL;
    self.p15card = NULL;
    self.ctx = NULL;
}


- (TKTokenSession *)token:(TKToken *)token createSessionWithError:(NSError * _Nullable __autoreleasing *)error {
    return [[OpenSCTokenSession alloc] initWithToken:self];
}

@end
