//
//  LoginWindowController.m
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

#import "LoginWindowController.h"

@interface LoginWindowController () <NSWindowDelegate>
@end

@implementation LoginWindowController

- (instancetype)init {
    return [super initWithWindowNibName:@"Login"];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self.usernameField setStringValue:@""];
    [self.passwordField setStringValue:@""];
    [self.errorLabel setHidden:YES];
    [self.progressIndicator setHidden:YES];
    [self.progressIndicator stopAnimation:nil];
    [self.window setDelegate:self];
}

- (IBAction)logIn:(id)sender {
    NSCharacterSet *spaces = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *username = [[self.usernameField stringValue] stringByTrimmingCharactersInSet:spaces];
    NSString *password = [self.passwordField stringValue];

    if (username.length == 0 || password.length == 0) {
        [self showLoginFailedWithMessage:NSLocalizedString(@"Enter staff ID and PIN.",
                                                            @"Login form validation error.")];
        return;
    }

    [self.errorLabel setHidden:YES];
    [self setFormEnabled:NO];
    [self.progressIndicator setHidden:NO];
    [self.progressIndicator startAnimation:nil];

    [self.delegate loginWindowController:self didSubmitWithUsername:username password:password];
}

- (IBAction)quit:(id)sender {
    [self.delegate loginWindowControllerDidCancel:self];
}

- (void)showLoginFailedWithMessage:(NSString *)message {
    [self.progressIndicator stopAnimation:nil];
    [self.progressIndicator setHidden:YES];
    [self setFormEnabled:YES];
    [self.passwordField setStringValue:@""];
    NSString *text = message.length > 0
        ? message
        : NSLocalizedString(@"Login failed. Check your staff ID and PIN.",
                            @"Inline login failure message.");
    [self.errorLabel setStringValue:text];
    [self.errorLabel setHidden:NO];
    [self.window makeFirstResponder:self.passwordField];
}

- (void)showLoginSucceeded {
    [self.progressIndicator stopAnimation:nil];
    [self.progressIndicator setHidden:YES];
    [self.errorLabel setHidden:YES];
    [self.window orderOut:nil];
}

- (void)setFormEnabled:(BOOL)enabled {
    [self.usernameField setEnabled:enabled];
    [self.passwordField setEnabled:enabled];
    [self.loginButton setEnabled:enabled];
}

#pragma mark - NSWindowDelegate

- (BOOL)windowShouldClose:(NSWindow *)sender {
    [self.delegate loginWindowControllerDidCancel:self];
    return NO;
}

@end
