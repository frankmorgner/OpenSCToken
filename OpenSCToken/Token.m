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

- (nullable instancetype)initWithSmartCard:(TKSmartCard *)smartCard AID:(nullable NSData *)AID OpenSCDriver:(OpenSCTokenDriver *)tokenDriver error:(NSError * _Nullable __autoreleasing *)error {
    
    sc_context_param_t ctx_param;
    sc_context_t *ctx = NULL;
    sc_card_t *card = NULL;
    sc_pkcs15_card_t *p15card = NULL;
    struct sc_app_info *app_generic = NULL;
    struct sc_aid *aid = NULL;
    struct sc_pkcs15_object *objs[32];
    int r;
    size_t i, cert_num;
    NSMutableArray<TKTokenKeychainItem *> *items;
    NSString *instanceID = nil;
    
    /* TODO: Move card and p15card to smartCard.context. smartCard.context would automatically be set to nil if the card gets reset or the state gets modified by a different session, see documentation for TKSmartCard */
    
    self.card = NULL;
    self.p15card = NULL;
    self.ctx = NULL;

    os_log(OS_LOG_DEFAULT, "%s", OPENSC_SCM_REVISION);

    /* Respect the App's sandbox; use only bundled resources */
    NSString *Resources = [[NSBundle mainBundle] resourcePath];
    NSString * opensc_conf = [[NSBundle mainBundle] pathForResource:@"opensc" ofType:@"conf"];
    NSArray* Documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    os_log(OS_LOG_DEFAULT, "For logging and persistent data cache please use %@", Documents.lastObject);
    if (opensc_conf != nil) {
        os_log(OS_LOG_DEFAULT, "Reading configuration %@", opensc_conf);
        setenv("OPENSC_CONF", opensc_conf.fileSystemRepresentation, 0);
    }

    memset(&ctx_param, 0, sizeof(ctx_param));
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
    
    r = sc_pkcs15_get_objects(p15card, SC_PKCS15_TYPE_CERT_X509, objs, sizeof(objs)/(sizeof *objs));
    LOG_TEST_GOTO_ERR(ctx, r, "sc_pkcs15_get_objects (SC_PKCS15_TYPE_CERT_X509)");
    cert_num = (size_t) r;
    items = [NSMutableArray arrayWithCapacity:cert_num];
    for (i = 0; i < cert_num; i++) {
        struct sc_pkcs15_cert_info *cert_info = objs[i]->data;
        struct sc_pkcs15_cert *cert = NULL;
        struct sc_pkcs15_object *prkey_obj = NULL;

        r = sc_pkcs15_read_certificate(p15card, cert_info, &cert);
        if (r) {
            sc_log(ctx, "sc_pkcs15_read_certificate: %s", sc_strerror(r));
            continue;
        }
        NSData* certificateData = [NSData dataWithBytes:(const void *)cert->data.value length:sizeof(unsigned char)*cert->data.len];
        NSData* certificateID = [NSData dataWithBytes:cert_info->id.value length:cert_info->id.len];
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
        struct sc_pkcs15_prkey_info *prkey_info = (struct sc_pkcs15_prkey_info *) prkey_obj->data;
        NSData* keyID = [NSData dataWithBytes:prkey_info->id.value length:prkey_info->id.len];
        NSString *keyName = [NSString stringWithUTF8String:objs[i]->label];
        TKTokenKeychainKey *keyItem = [[TKTokenKeychainKey alloc] initWithCertificate:(__bridge SecCertificateRef)certificate objectID:keyID];
        if (keyID == nil || keyName == nil || keyItem == nil) {
            continue;
        }
        [keyItem setName:keyName];

        NSMutableDictionary<NSNumber *, TKTokenOperationConstraint> *constraints = [NSMutableDictionary dictionary];
        TKTokenOperationConstraint constraint;
        if (prkey_obj->auth_id.len == 0) {
            /* true, indicating that the operation is always allowed, without any authentication necessary. */
            constraint = @YES;
        } else {
            /* Any other property list compatible value defined by the implementation of the token extension. Any such constraint is required to stay constant for the entire lifetime of the token. */
            constraint = [NSData dataWithBytes:(const void *)prkey_obj->auth_id.value length:prkey_obj->auth_id.len];
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
        [items addObject:keyItem];
    }

    instanceID = [NSString stringWithUTF8String:p15card->tokeninfo->serial_number];
    p15card->opts.use_pin_cache = 0;
    
    if (self = [super initWithSmartCard:smartCard AID:AID instanceID:instanceID tokenDriver:tokenDriver]) {
        [self.keychainContents fillWithItems:items];
        
        self.ctx = ctx;
        self.card = card;
        self.p15card = p15card;
    } else {
        goto err;
    }
    
err:
    if (!self.p15card && p15card)
        sc_pkcs15_card_free(p15card);
    if (!self.card && card)
        sc_disconnect_card(card);
    if (!self.ctx && ctx)
        sc_release_context(ctx);
    return self;
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
