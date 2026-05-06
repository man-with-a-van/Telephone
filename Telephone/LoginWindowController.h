//
//  LoginWindowController.h
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

@import Cocoa;

NS_ASSUME_NONNULL_BEGIN

@class LoginWindowController;

@protocol LoginWindowControllerDelegate <NSObject>

- (void)loginWindowController:(LoginWindowController *)controller
       didSubmitWithUsername:(NSString *)username
                    password:(NSString *)password;

- (void)loginWindowControllerDidCancel:(LoginWindowController *)controller;

@end

@interface LoginWindowController : NSWindowController

@property(nonatomic, weak) id<LoginWindowControllerDelegate> delegate;

@property(nonatomic, weak) IBOutlet NSTextField *usernameField;
@property(nonatomic, weak) IBOutlet NSSecureTextField *passwordField;
@property(nonatomic, weak) IBOutlet NSTextField *errorLabel;
@property(nonatomic, weak) IBOutlet NSProgressIndicator *progressIndicator;
@property(nonatomic, weak) IBOutlet NSButton *loginButton;
@property(nonatomic, weak) IBOutlet NSButton *quitButton;

- (instancetype)init;

- (IBAction)logIn:(id)sender;
- (IBAction)quit:(id)sender;

// Called by AppController once a registration attempt completes.
- (void)showLoginFailedWithMessage:(nullable NSString *)message;
- (void)showLoginSucceeded;

@end

NS_ASSUME_NONNULL_END
