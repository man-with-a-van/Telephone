//
//  MWAVCallerIDNotifier.m
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

#import "MWAVCallerIDNotifier.h"

#import "AKSIPAccount.h"
#import "AKSIPCall.h"
#import "AKSIPURI.h"

NSString * const MWAVCallerIDStateRinging = @"ringing";
NSString * const MWAVCallerIDStateAnswered = @"answered";
NSString * const MWAVCallerIDStateEnded = @"ended";

static const NSTimeInterval kRequestTimeout = 5;

static BOOL HasDigits(NSString *string) {
    return [string rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location != NSNotFound;
}

@implementation MWAVCallerIDNotifier

+ (void)notifyCall:(AKSIPCall *)call callID:(NSString *)callID state:(NSString *)state {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *URLString = info[@"MWAVCallerIDURL"];
    NSString *key = info[@"MWAVCallerIDKey"];
    NSURL *URL = URLString.length > 0 ? [NSURL URLWithString:URLString] : nil;
    if (URL == nil || key.length == 0 || callID.length == 0) {
        return;
    }

    NSDictionary *body = @{
        @"ID_ResourceStaff": call.account.username ?: @"",
        @"number": [self numberForCall:call],
        @"state": state,
        @"callId": callID,
    };
    NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    if (payload == nil) {
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:kRequestTimeout];
    request.HTTPMethod = @"POST";
    request.HTTPBody = payload;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    // A dev backend behind ngrok otherwise answers with its HTML warning page.
    [request setValue:@"1" forHTTPHeaderField:@"ngrok-skip-browser-warning"];

    [[NSURLSession.sharedSession dataTaskWithRequest:request
                                   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        if (error != nil || status != 200) {
            NSLog(@"Caller ID %@ not delivered (HTTP %ld): %@", state, (long)status, error.localizedDescription ?: @"");
        }
    }] resume];
}

// The backend normalises the number and decides when it's withheld, so this
// sends it as the phone system gave it. Some systems put the number in the
// display name and an opaque id in the user part.
+ (NSString *)numberForCall:(AKSIPCall *)call {
    NSString *user = call.remoteURI.user ?: @"";
    NSString *displayName = call.remoteURI.displayName ?: @"";
    if (!HasDigits(user) && HasDigits(displayName)) {
        return displayName;
    }
    return user;
}

@end
