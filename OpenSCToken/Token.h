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
 * pcsc-relay is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * pcsc-relay.  If not, see <http://www.gnu.org/licenses/>.
 */
@import Foundation;
@import CryptoTokenKit;
@import CryptoTokenKit.TKSmartCardToken;

#include "libopensc/pkcs15.h"

NS_ASSUME_NONNULL_BEGIN


#pragma mark OpenSC implementation of TKToken classes

@class OpenSCTokenDriver;
@class OpenSCToken;
@class OpenSCTokenSession;

@interface OpenSCTokenSession : TKSmartCardTokenSession<TKTokenSessionDelegate>
- (instancetype)initWithToken:(TKToken *)token delegate:(id<TKTokenSessionDelegate>)delegate NS_UNAVAILABLE;

- (instancetype)initWithToken:(OpenSCToken *)token;
@property (readonly) OpenSCToken *OpenSCToken;

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
