//
//  CallDestinationTokenField.h
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

// NSTokenField subclass that returns a fixed intrinsic content size to keep
// AppKit from querying NSTokenFieldCell's editor during constraint updates.
// Without this override, computing the cell's size goes through
// _validateEditing, which re-commits the editor's value, invalidates the
// intrinsic size, and reschedules another constraint pass — an Auto Layout
// loop that aborts the window's display cycle and stalls the dialer.
@interface CallDestinationTokenField : NSTokenField
@end

NS_ASSUME_NONNULL_END
