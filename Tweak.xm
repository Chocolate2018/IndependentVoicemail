#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <unistd.h>
#import <stdarg.h>

static NSString * const IVLogPath =
    @"/var/mobile/Library/Preferences/IndependentVoicemailV1.log";

static void IVLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);

    NSString *s =
        [[NSString alloc] initWithFormat:format arguments:args];

    va_end(args);

    NSString *line =
        [NSString stringWithFormat:@"%@ %@\n",
         [NSDate date], s];

    NSFileHandle *h =
        [NSFileHandle fileHandleForWritingAtPath:IVLogPath];

    if (!h) {
        [[NSFileManager defaultManager]
            createFileAtPath:IVLogPath
            contents:nil
            attributes:nil];

        h =
            [NSFileHandle fileHandleForWritingAtPath:IVLogPath];
    }

    if (h) {
        [h seekToEndOfFile];

        NSData *data =
            [line dataUsingEncoding:NSUTF8StringEncoding];

        [h writeData:data];
        [h closeFile];
    }
}

static void IVHandleCallNotification(NSNotification *note) {

    NSString *name = note.name;

    if ([name isEqualToString:@"SBIncomingCallPendingNotification"]) {

        IVLog(@"--------------------------------");
        IVLog(@"INCOMING CALL EVENT DETECTED");
        IVLog(@"Notification: %@", name);
        IVLog(@"Object: %@", note.object);
        IVLog(@"UserInfo: %@", note.userInfo);
        IVLog(@"--------------------------------");

        return;
    }

    if ([name isEqualToString:
         @"TUCallCenterCallStatusChangedNotification"]) {

        IVLog(@"CALL STATUS CHANGED");
        IVLog(@"Object: %@", note.object);
        IVLog(@"UserInfo: %@", note.userInfo);

        return;
    }

    if ([name isEqualToString:
         @"TUCallCenterCallStatusChangedInternalNotification"]) {

        IVLog(@"CALL INTERNAL STATUS CHANGED");
        IVLog(@"Object: %@", note.object);
        IVLog(@"UserInfo: %@", note.userInfo);

        return;
    }

    if ([name isEqualToString:
         @"SBCallCountChangedNotification"]) {

        IVLog(@"CALL COUNT CHANGED");
        IVLog(@"Object: %@", note.object);
        IVLog(@"UserInfo: %@", note.userInfo);

        return;
    }
}

%ctor {
    @autoreleasepool {

        IVLog(@"================================");
        IVLog(@"IndependentVoicemail v1.3 LOADED");
        IVLog(@"Process: SpringBoard");
        IVLog(@"PID: %d", getpid());

        NSArray *names = @[
            @"SBIncomingCallPendingNotification",
            @"SBCallCountChangedNotification",
            @"TUCallCenterCallStatusChangedNotification",
            @"TUCallCenterCallStatusChangedInternalNotification",
            @"TUCallTransmissionStateChangedNotification",
            @"TUCallCenterCallerIDChangedNotification",
            @"TUCallCenterModelStateChangedNotification",
            @"TUCallCenterProviderContextChangedNotification"
        ];

        NSNotificationCenter *center =
            [NSNotificationCenter defaultCenter];

        for (NSString *name in names) {

            [center addObserverForName:name
                                object:nil
                                 queue:nil
                            usingBlock:^(NSNotification *note) {

                IVHandleCallNotification(note);

            }];
        }

        IVLog(@"Call state observers installed");
        IVLog(@"================================");
    }
}
