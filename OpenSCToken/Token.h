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
@import Foundation;
@import CryptoTokenKit;
@import CryptoTokenKit.TKSmartCardToken;

#include "libopensc/pkcs15.h"
#include "libopensc/cards.h"
#include "libopensc/cardctl.h"

#define TYPE_CERT 0x01
#define TYPE_PRIV 0x02
#define TYPE_AUTH 0x03

/*
 * OpenSC exposes the YubiKey PIV PIN policy through card_ctl.  Checking the
 * policy on the card avoids both an unnecessary CryptoTokenKit PIN prompt for
 * PIN-NEVER keys and unsafe assumptions based only on the PIV slot number.
 */
static BOOL isPINNeverYubiKeyKey(struct sc_pkcs15_card * _Nullable p15card,
                                struct sc_pkcs15_object * _Nullable obj)
{
    if (p15card == NULL || p15card->card == NULL || obj == NULL || obj->data == NULL)
        return NO;

    if (p15card->card->type != SC_CARD_TYPE_PIV_II_YUBIKEY4)
        return NO;

    if ((obj->type & SC_PKCS15_TYPE_CLASS_MASK) != SC_PKCS15_TYPE_PRKEY)
        return NO;

    struct sc_pkcs15_prkey_info *keyInfo = obj->data;
    u8 pinPolicy = keyInfo->key_reference;
    int r = sc_card_ctl(p15card->card, SC_CARDCTL_PIV_YK_PIN_POLICY, &pinPolicy);
    return r == SC_SUCCESS && pinPolicy == 0x01;
}

static NSData* _Nullable idToData(u8 type, struct sc_pkcs15_id * _Nullable p15id)
{
    NSData *data = nil;
    if (p15id) {
        u8 *p = malloc(p15id->len+1);
        if (p) {
            *p = type;
            memcpy(p+1, p15id->value, p15id->len);
            data = [NSData dataWithBytes:p length:p15id->len+1];
            free(p);
        }
    }
    return data;
}

static struct sc_pkcs15_id dataToId(NSData* _Nonnull data)
{
    struct sc_pkcs15_id p15id;
    p15id.len = [data length];
    memcpy(p15id.value, [data bytes], p15id.len);
    if (p15id.len > 0) {
        p15id.len--;
        memmove(p15id.value, p15id.value+1, p15id.len);
    }
    return p15id;
}

NS_ASSUME_NONNULL_BEGIN


#pragma mark OpenSC implementation of TKToken classes

@class OpenSCTokenDriver;
@class OpenSCToken;
@class OpenSCTokenSession;

@interface OpenSCTokenSession : TKSmartCardTokenSession<TKTokenSessionDelegate>
- (instancetype)initWithToken:(TKToken *)token delegate:(id<TKTokenSessionDelegate>)delegate NS_UNAVAILABLE;

- (instancetype)initWithToken:(OpenSCToken *)token;
@property (readonly) OpenSCToken *OpenSCToken;
@property BOOL needs_user_consent;

@end

@interface OpenSCToken : TKSmartCardToken<TKTokenDelegate>
- (instancetype)initWithSmartCard:(TKSmartCard *)smartCard AID:(nullable NSData *)AID tokenDriver:(TKSmartCardTokenDriver *)tokenDriver delegate:(id<TKTokenDelegate>)delegate NS_UNAVAILABLE;

- (nullable instancetype)initWithSmartCard:(TKSmartCard *)smartCard AID:(nullable NSData *)AID OpenSCDriver:(OpenSCTokenDriver *)tokenDriver error:(NSError **)error;
@property (readonly) OpenSCTokenDriver *driver;
@property (nonatomic, assign, nullable) struct sc_context *ctx;
@property (nonatomic, assign, nullable) struct sc_card *card;
@property (nonatomic, assign, nullable) struct sc_pkcs15_card *p15card;

@end

@interface OpenSCTokenDriver : TKSmartCardTokenDriver<TKSmartCardTokenDriverDelegate>
@end

NS_ASSUME_NONNULL_END
