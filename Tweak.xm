#import <Foundation/Foundation.h>
#import <objc/runtime.h>
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

static void IVInspectObject(id object) {

    if (!object) {
        IVLog(@"Notification object = nil");
        return;
    }

    Class cls = object_getClass(object);

    IVLog(@"--------------------------------");
    IVLog(@"CALL OBJECT INSPECTION");
    IVLog(@"Class: %@", NSStringFromClass(cls));

    if ([object respondsToSelector:@selector(description)]) {
        IVLog(@"Description: %@", [object description]);
    }

    unsigned int count = 0;

    Method *methods = class_copyMethodList(cls, &count);

    IVLog(@"Instance method count: %u", count);

    for (unsigned int i = 0; i < count; i++) {

        SEL sel = method_getName(methods[i]);
        const char *name = sel_getName(sel);

        NSString *selector =
            [NSString stringWithUTF8String:name];

        NSString *lower =
            [selector lowercaseString];

        /*
         * 只记录与电话状态/接听有关的方法。
         */
        if ([lower containsString:@"answer"] ||
            [lower containsString:@"accept"] ||
            [lower containsString:@"hold"] ||
            [lower containsString:@"disconnect"] ||
            [lower containsString:@"end"] ||
            [lower containsString:@"state"] ||
            [lower containsString:@"status"] ||
            [lower containsString:@"call"]) {

            IVLog(@"Selector: %@", selector);
        }
    }

    free(methods);

    IVLog(@"--------------------------------");
}

static void IVHandleNotification(NSNotification *note) {

    if ([note.name
         isEqualToString:@"SBIncomingCallPendingNotification"]) {

        IVLog(@"INCOMING CALL DETECTED");
        IVInspectObject(note.object);

        if (note.userInfo) {
            IVLog(@"UserInfo: %@", note.userInfo);
        }

        return;
    }

    if ([note.name
         isEqualToString:
         @"TUCallCenterCallStatusChangedNotification"]) {

        IVLog(@"TU CALL STATUS CHANGED");
        IVInspectObject(note.object);

        if (note.userInfo) {
            IVLog(@"UserInfo: %@", note.userInfo);
        }

        return;
    }

    if ([note.name
         isEqualToString:
         @"TUCallCenterCallStatusChangedInternalNotification"]) {

        IVLog(@"TU CALL INTERNAL STATUS CHANGED");
        IVInspectObject(note.object);

        if (note.userInfo) {
            IVLog(@"UserInfo: %@", note.userInfo);
        }

        return;
    }
}

%ctor {
    @autoreleasepool {

        IVLog(@"================================");
        IVLog(@"IndependentVoicemail v1.5 LOADED");
        IVLog(@"Process: SpringBoard");
        IVLog(@"PID: %d", getpid());

        NSArray *names = @[
            @"SBIncomingCallPendingNotification",
            @"TUCallCenterCallStatusChangedNotification",
            @"TUCallCenterCallStatusChangedInternalNotification"
        ];

        NSNotificationCenter *center =
            [NSNotificationCenter defaultCenter];

        for (NSString *name in names) {

            [center addObserverForName:name
                                object:nil
                                 queue:nil
                            usingBlock:^(NSNotification *note) {

                IVHandleNotification(note);

            }];
        }

        IVLog(@"Call object inspector installed");
        IVLog(@"================================");
    }
}
