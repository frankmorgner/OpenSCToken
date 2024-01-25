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

/* in sync with SC_PKCS11_FRAMEWORK_DATA_MAX_NUM */
#define SC_TOKEN_APPS_MAX_NUM    4
struct token_apps {
    struct sc_pkcs15_card * _Nullable p15card[SC_TOKEN_APPS_MAX_NUM];
};

#define TYPE_CERT 0x01
#define TYPE_PRIV 0x02
#define TYPE_AUTH 0x03

/* The converted data consists of app_index+type+p15id. This allows identifying which on-card-application has this object if there are multiple applications. And this allows differentiating different types of objects with the same p15id. */
static NSData* _Nullable idToData(u8 index, u8 type, struct sc_pkcs15_id * _Nullable p15id)
{
    NSData *data = nil;
    if (p15id) {
        u8 *p = malloc(p15id->len+2);
        if (p) {
            p[0] = index;
            p[1] = type;
            memcpy(&p[2], p15id->value, p15id->len);
            data = [NSData dataWithBytes:p length:p15id->len+2];
            free(p);
        }
    }
    return data;
}

static struct sc_pkcs15_id dataToId(NSData* _Nonnull data, u8 * _Nullable index)
{
    struct sc_pkcs15_id p15id = {0};
    size_t data_len = [data length];
    const unsigned char *p = [data bytes];
    if (data_len > 1 && p) {
        if (index)
            *index = p[0];
        memcpy(p15id.value, &p[2], data_len-2);
        p15id.len = data_len-2;
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
@property (nonatomic, assign) struct token_apps apps;

@end

@interface OpenSCTokenDriver : TKSmartCardTokenDriver<TKSmartCardTokenDriverDelegate>
@end

NS_ASSUME_NONNULL_END
