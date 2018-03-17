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

#import "Token.h"

@implementation OpenSCTokenDriver

- (TKSmartCardToken *)tokenDriver:(TKSmartCardTokenDriver *)driver createTokenForSmartCard:(TKSmartCard *)smartCard AID:(NSData *)AID error:(NSError * _Nullable __autoreleasing *)error {
    return [[OpenSCToken alloc] initWithSmartCard:smartCard AID:AID OpenSCDriver:self error:error];
}

@end
